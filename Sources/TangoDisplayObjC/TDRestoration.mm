//
//  TDRestoration.mm
//
//  In-process Audio Units wrapping the ShellacFilters declick and dehum DSP cores.
//  Cores: https://github.com/shaforostoff/shellacfilters — (c) 2026 Nick Shaforostov,
//  (c) 2018 Chris Johnson, MIT. See shellac/LICENSE.txt.
//
//  The wrapper is adapted from EmbraceNG's RestorationAudioUnit.mm,
//  (c) 2024 Ricci Adams, MIT / 1-clause BSD.
//
//  Two deliberate departures from that reference, both because the host differs:
//
//   * Declick primes rather than reading ahead. EmbraceNG pulls its input block
//     repeatedly with an unchanged timestamp until the pipeline can satisfy the
//     render, spending read position instead of latency. Its upstream is a custom
//     source AU; ours is AVAudioPlayerNode, which caches its render by mSampleTime
//     and would hand back the same block every time round that loop. So we feed
//     `latency` zeros once and accept cfg.latency of delay — 784 samples, 17.8 ms
//     at 44.1 kHz — declared through -latency.
//
//   * Declick also gets the per-track reset that EmbraceNG gives only to dehum, so
//     the previous record's tail does not bleed 18 ms into the next one.
//

#import "include/TDRestoration.h"

#import "shellac/declick_core.h"
#import "shellac/dehum_core.h"

#import <AVFoundation/AVFoundation.h>
#import <os/log.h>

#include <atomic>
#include <algorithm>
#include <cmath>
#include <vector>

const OSType TDRestorationManufacturer = 'TgDs';
const OSType TDDeclickSubType          = 'dclk';
const OSType TDDehumSubType            = 'dhum';

static const int sMaxChannels   = 2;
static const int sMaxParameters = 8;

static os_log_t sLog(void)
{
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.tangodisplay", "Restoration"); });
    return log;
}


// Bypass runs the DSP with a wet mix of zero rather than skipping it, which is what
// makes A/B useful: dehum's detector keeps tracking, so switching back does not cost
// the several seconds it takes to re-acquire a line, and declick keeps its pipeline
// full so the two versions line up sample for sample.
//
struct TDRestorationState {
    std::atomic<float> value[sMaxParameters];
    std::atomic<bool>  bypassed;

    float defaultValue[sMaxParameters];

    TDRestorationState() : bypassed(false)
    {
        for (int i = 0; i < sMaxParameters; i++) {
            value[i].store(0, std::memory_order_relaxed);
            defaultValue[i] = 0;
        }
    }

    float get(int index) const { return value[index].load(std::memory_order_relaxed); }
    bool  isBypassed()   const { return bypassed.load(std::memory_order_relaxed); }
};


// AVAudioEngine always hands us real buffers. A host that does not is asking the unit
// to supply its own, which we do not.
static AUAudioUnitStatus sPrepareBufferList(AudioBufferList *bufferList, AUAudioFrameCount frameCount)
{
    for (UInt32 i = 0; i < bufferList->mNumberBuffers; i++) {
        if (!bufferList->mBuffers[i].mData) return kAudioUnitErr_InvalidParameter;
        bufferList->mBuffers[i].mDataByteSize = frameCount * sizeof(float);
    }

    return noErr;
}


static AUParameter *sMakeParameter(
    NSString *identifier, NSString *name, AUParameterAddress address,
    AUValue min, AUValue max, AUValue value, AudioUnitParameterUnit unit)
{
    AUParameter *parameter = [AUParameterTree
        createParameterWithIdentifier: identifier
                                 name: name
                              address: address
                                  min: min
                                  max: max
                                 unit: unit
                             unitName: nil
                                flags: kAudioUnitParameterFlag_IsReadable |
                                       kAudioUnitParameterFlag_IsWritable
                         valueStrings: nil
                  dependentParameters: nil];

    [parameter setValue:value];

    return parameter;
}


#pragma mark - Base Unit

// Track-scoped hooks. Both are no-ops on the base class so the C entry points can
// take any AUAudioUnit and do the right thing.
@protocol TDTrackScoped <NSObject>
- (void) td_forgetTrack;
@optional
- (void) td_scoutFileURL:(NSURL *)fileURL;
@end


@interface TDRestorationUnit : AUAudioUnit <TDTrackScoped>

// Subclass hooks, all main thread. The DSP is built once in -init and freed in
// -dealloc so its address never moves: a render block captures that pointer, and a
// graph rebuild can leave an old block running for a moment after a new one has
// been handed out.
- (void) createDSP;
- (void) destroyDSP;
- (void) configureDSPWithSampleRate:(double)sampleRate channels:(int)channels;
- (NSArray<AUParameter *> *) createParameters;
- (AUInternalRenderBlock) createRenderBlock;

@property (nonatomic, readonly) TDRestorationState *state;

@end


@implementation TDRestorationUnit {
    AUAudioUnitBusArray *_inputBusArray;
    AUAudioUnitBusArray *_outputBusArray;
    AUAudioUnitBus      *_inputBus;
    AUAudioUnitBus      *_outputBus;
    AUParameterTree     *_parameterTree;

    TDRestorationState  *_state;
}

@synthesize parameterTree = _parameterTree;
@synthesize state = _state;


- (instancetype) initWithComponentDescription:(AudioComponentDescription)componentDescription
                                      options:(AudioComponentInstantiationOptions)options
                                        error:(NSError **)outError
{
    if ((self = [super initWithComponentDescription:componentDescription options:options error:outError])) {
        _state = new TDRestorationState();

        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];

        _inputBus  = [[AUAudioUnitBus alloc] initWithFormat:format error:nil];
        _outputBus = [[AUAudioUnitBus alloc] initWithFormat:format error:nil];

        // Mono matters here: TangoDisplay wires the restoration nodes with the file's
        // own processingFormat, and plenty of shellac transfers are mono. Declick works
        // on mono, unlike the Airwindows declicker it replaces.
        [_inputBus  setMaximumChannelCount:sMaxChannels];
        [_outputBus setMaximumChannelCount:sMaxChannels];

        _inputBusArray  = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeInput  busses:@[ _inputBus  ]];
        _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeOutput busses:@[ _outputBus ]];

        NSArray<AUParameter *> *parameters = [self createParameters];
        _parameterTree = [AUParameterTree createTreeWithChildren:parameters];

        TDRestorationState *state = _state;

        for (AUParameter *parameter in parameters) {
            AUParameterAddress address = [parameter address];

            state->value[address].store([parameter value], std::memory_order_relaxed);
            state->defaultValue[address] = [parameter value];
        }

        [_parameterTree setImplementorValueObserver:^(AUParameter *parameter, AUValue value) {
            state->value[[parameter address]].store(value, std::memory_order_relaxed);
        }];

        [_parameterTree setImplementorValueProvider:^AUValue(AUParameter *parameter) {
            return state->value[[parameter address]].load(std::memory_order_relaxed);
        }];

        [self createDSP];
        [self configureDSPWithSampleRate:44100 channels:2];
    }

    return self;
}


- (void) dealloc
{
    [self destroyDSP];

    delete _state;
    _state = NULL;
}


- (AUAudioUnitBusArray *) inputBusses  { return _inputBusArray;  }
- (AUAudioUnitBusArray *) outputBusses { return _outputBusArray; }

- (BOOL) canProcessInPlace { return YES; }


- (BOOL) allocateRenderResourcesAndReturnError:(NSError **)outError
{
    if (![super allocateRenderResourcesAndReturnError:outError]) {
        return NO;
    }

    AVAudioFormat *format = [_outputBus format];

    // The cores only touch the heap on their first configure at a given sample rate,
    // so getting that one out of the way here is what keeps every later parameter
    // move allocation-free on the render thread.
    [self configureDSPWithSampleRate: [format sampleRate]
                            channels: std::min((int)[format channelCount], sMaxChannels)];

    return YES;
}


- (void) setShouldBypassEffect:(BOOL)shouldBypassEffect
{
    [super setShouldBypassEffect:shouldBypassEffect];
    _state->bypassed.store(shouldBypassEffect ? true : false, std::memory_order_relaxed);
}


- (AUInternalRenderBlock) internalRenderBlock
{
    return [self createRenderBlock];
}


#pragma mark - Subclass Hooks

- (void) createDSP { }
- (void) destroyDSP { }
- (void) configureDSPWithSampleRate:(double)sampleRate channels:(int)channels { }
- (NSArray<AUParameter *> *) createParameters { return @[ ]; }
- (AUInternalRenderBlock) createRenderBlock { return nil; }
- (void) td_forgetTrack { }

@end


#pragma mark - Declick

struct TDDeclickDSP {
    declick::Channel channel[sMaxChannels];
    declick::Params  active;
    declick::Config  cfg;

    double sampleRate = 44100;
    int    channels   = 2;
    bool   haveActive = false;
    bool   configured = false;

    std::atomic<bool> forgetPending;

    TDDeclickDSP() : forgetPending(false) { }

    declick::Params paramsFrom(const TDRestorationState *state) const
    {
        declick::Params p = declick::Params::defaults();

        p.sensitivity = state->get(TDDeclickParamSensitivity);
        p.extent      = state->get(TDDeclickParamExtent);
        p.maxLengthMs = state->get(TDDeclickParamMaxLengthMs);
        p.depth       = state->get(TDDeclickParamDepth);
        p.passes      = (int)lrintf(state->get(TDDeclickParamPasses));
        p.order       = (int)lrintf(state->get(TDDeclickParamOrder));
        p.dryWet      = state->isBypassed() ? 0.0f : state->get(TDDeclickParamDryWet);
        p.sanitize();

        return p;
    }

    //! Feed `latency` zeros so available() >= n holds after every subsequent push of
    //! n, for any n. Allocation-free — it only runs zeros through buffers the channel
    //! already holds — so the render thread may call it.
    void primeAll()
    {
        for (int i = 0; i < channels; i++) channel[i].prime();
    }

    void update(const TDRestorationState *state)
    {
        // A new record means a fresh pipeline. reset() empties it, so it has to be
        // re-primed or the next pull underruns.
        if (forgetPending.exchange(false, std::memory_order_relaxed)) {
            for (int i = 0; i < channels; i++) channel[i].reset();
            primeAll();
        }

        declick::Params p = paramsFrom(state);
        if (haveActive && p == active) return;

        declick::Config next;
        next.compute(p, sampleRate);

        if (configured && next.structurallyEquals(cfg)) {
            bool retuned = true;

            for (int i = 0; i < channels; i++) {
                if (!channel[i].retune(next)) retuned = false;
            }

            if (retuned) {
                cfg = next;
                active = p;
                haveActive = true;
                return;
            }
        }

        // Only Max Repair and Model Order reach here. Past the first call it allocates
        // nothing — see the buffer envelope in declick::Config — but configure() empties
        // the pipeline, so it has to be primed again before the next pull.
        for (int i = 0; i < channels; i++) {
            channel[i].configure(next);
        }
        primeAll();

        cfg = next;
        active = p;
        haveActive = true;
        configured = true;
    }

    void restart(double rate, int chans)
    {
        sampleRate = rate;
        channels   = chans;
        haveActive = false;
        configured = false;
    }

    void process(AudioBufferList *bufferList, AUAudioFrameCount frames)
    {
        int count = std::min((int)bufferList->mNumberBuffers, channels);

        for (int i = 0; i < count; i++) {
            float *data = (float *)bufferList->mBuffers[i].mData;

            channel[i].push(data, frames, 1);

            // Cannot underrun: primeAll() put `latency` samples of head start into the
            // pipeline and every configure()/reset() above restores it.
            if (channel[i].available() >= frames) {
                channel[i].pull(data, frames, 1);
            } else {
                memset(data, 0, frames * sizeof(float));
            }
        }
    }
};


@interface TDDeclickUnit : TDRestorationUnit
@end


@implementation TDDeclickUnit {
    TDDeclickDSP *_dsp;
}

- (NSArray<AUParameter *> *) createParameters
{
    declick::Params defaults = declick::Params::defaults();

    return @[
        sMakeParameter(@"sensitivity", @"Sensitivity",  TDDeclickParamSensitivity, 0,   1,  defaults.sensitivity, kAudioUnitParameterUnit_Generic),
        sMakeParameter(@"extent",      @"Extent",       TDDeclickParamExtent,      0,   1,  defaults.extent,      kAudioUnitParameterUnit_Generic),
        sMakeParameter(@"maxLength",   @"Max Repair",   TDDeclickParamMaxLengthMs, 0.2, 20, defaults.maxLengthMs, kAudioUnitParameterUnit_Milliseconds),
        sMakeParameter(@"depth",       @"Repair Depth", TDDeclickParamDepth,       0,   1,  defaults.depth,       kAudioUnitParameterUnit_Generic),
        sMakeParameter(@"passes",      @"Passes",       TDDeclickParamPasses,      1,   3,  defaults.passes,      kAudioUnitParameterUnit_Indexed),
        sMakeParameter(@"order",       @"Model Order",  TDDeclickParamOrder,       declick::kMinOrder, declick::kMaxOrder, defaults.order, kAudioUnitParameterUnit_Indexed),
        sMakeParameter(@"dryWet",      @"Dry/Wet",      TDDeclickParamDryWet,      0,   1,  defaults.dryWet,      kAudioUnitParameterUnit_Generic)
    ];
}


- (void) createDSP  { _dsp = new TDDeclickDSP(); }
- (void) destroyDSP { delete _dsp; _dsp = NULL; }


- (void) configureDSPWithSampleRate:(double)sampleRate channels:(int)channels
{
    _dsp->restart(sampleRate, channels);
    _dsp->update([self state]);
}


- (void) td_forgetTrack
{
    _dsp->forgetPending.store(true, std::memory_order_relaxed);
}


// The model's lookahead is paid as delay, not as read position — see the note at the
// top of this file. AVAudioEngine reads this to account for the node.
- (NSTimeInterval) latency
{
    if (!_dsp || !_dsp->configured || _dsp->sampleRate <= 0) return 0;
    return (NSTimeInterval)_dsp->cfg.latency / _dsp->sampleRate;
}


- (AUInternalRenderBlock) createRenderBlock
{
    TDDeclickDSP       *dsp   = _dsp;
    TDRestorationState *state = [self state];

    return ^AUAudioUnitStatus(
        AudioUnitRenderActionFlags *actionFlags,
        const AudioTimeStamp       *timestamp,
        AUAudioFrameCount           frameCount,
        NSInteger                   outputBusNumber,
        AudioBufferList            *outputData,
        const AURenderEvent        *realtimeEventListHead,
        AURenderPullInputBlock      pullInputBlock)
    {
        if (!pullInputBlock) return kAudioUnitErr_NoConnection;

        AUAudioUnitStatus err = sPrepareBufferList(outputData, frameCount);
        if (err) return err;

        AudioUnitRenderActionFlags pullFlags = 0;
        err = pullInputBlock(&pullFlags, timestamp, frameCount, 0, outputData);
        if (err) return err;

        // The AR fit and the Cholesky solve both run recursions down towards zero, so
        // denormals are reachable and expensive. Part of the numerical contract, not an
        // optimisation: the ports are only comparable while they all agree about it.
        declick::scoped_flush_denormals ftz;

        dsp->update(state);
        dsp->process(outputData, frameCount);

        return noErr;
    };
}

@end


#pragma mark - Dehum

struct TDDehumDSP {
    dehum::Channel channel[sMaxChannels];
    dehum::Params  active;
    dehum::Config  cfg;

    double sampleRate = 44100;
    int    channels   = 2;
    bool   haveActive = false;
    bool   configured = false;

    // Published by the main thread once a scout finishes, consumed on the render
    // thread. Handed to Channel::adopt(), which starts the lines confirmed and leaves
    // the detector running — so it keeps tracking them, drops them again if the
    // evidence is not really there, and can still find lines the scout missed.
    dehum::LineReport pendingLines[dehum::kMaxLines];
    int               pendingCount;
    std::atomic<bool> pendingReady;

    std::atomic<bool> forgetPending;

    // Bumped per track. A scout reads a minute of audio, which is long enough that
    // someone working through a setlist can leave several in flight.
    std::atomic<long> scoutGeneration;

    TDDehumDSP() : pendingCount(0), pendingReady(false), forgetPending(false), scoutGeneration(0) { }

    dehum::Params paramsFrom(const TDRestorationState *state) const
    {
        dehum::Params p = dehum::Params::defaults();

        p.sensitivity = state->get(TDDehumParamSensitivity);
        p.bandwidth   = state->get(TDDehumParamBandwidth);
        p.searchTo    = state->get(TDDehumParamSearchTo);
        p.harmonics   = (int)lrintf(state->get(TDDehumParamHarmonics));
        p.frequency   = state->get(TDDehumParamFrequency);
        p.rumbleHz    = state->get(TDDehumParamRumbleHz);
        p.dryWet      = state->isBypassed() ? 0.0f : state->get(TDDehumParamDryWet);
        p.sanitize();

        return p;
    }

    void update(const TDRestorationState *state)
    {
        // A new record means a new hum, so nothing carries over. reset() only memsets
        // buffers it already holds, so this is safe on the render thread.
        if (forgetPending.exchange(false, std::memory_order_relaxed)) {
            for (int i = 0; i < channels; i++) {
                channel[i].reset();
            }
        }

        dehum::Params p = paramsFrom(state);

        if (!haveActive || p != active) {
            dehum::Config next;
            next.compute(p, sampleRate);

            // Only the sample rate sizes anything here, so every parameter move retunes
            // in place and the lines already acquired survive it.
            bool retuned = configured && next.structurallyEquals(cfg);

            if (retuned) {
                for (int i = 0; i < channels; i++) {
                    if (!channel[i].retune(next)) retuned = false;
                }
            }

            if (!retuned) {
                for (int i = 0; i < channels; i++) {
                    channel[i].configure(next);
                }

                configured = true;
            }

            cfg = next;
            active = p;
            haveActive = true;
        }

        // Last of all, because configure() ends in reset() and would discard them.
        if (pendingReady.load(std::memory_order_acquire)) {
            // Copied out first: a track change can republish while we are here, and
            // adopt() should see one coherent set rather than half of two.
            dehum::LineReport lines[dehum::kMaxLines];
            int count = pendingCount;

            if (count > (int)dehum::kMaxLines) count = (int)dehum::kMaxLines;
            for (int i = 0; i < count; i++) lines[i] = pendingLines[i];

            pendingReady.store(false, std::memory_order_relaxed);

            for (int i = 0; i < channels; i++) {
                channel[i].adopt(lines, count);
            }
        }
    }

    void restart(double rate, int chans)
    {
        sampleRate = rate;
        channels   = chans;
        haveActive = false;
        configured = false;
    }

    void process(AudioBufferList *bufferList, AUAudioFrameCount frames)
    {
        int count = std::min((int)bufferList->mNumberBuffers, channels);

        for (int i = 0; i < count; i++) {
            channel[i].process((float *)bufferList->mBuffers[i].mData, frames, 1);
        }
    }
};


// Reads the opening of a file and returns the lines dehum settles on. Off the main
// thread.
//
// Analysed at the file's own sample rate, which saves resampling it: a hum sits at the
// same frequency in Hz whatever rate you look at it from, so the figures transfer
// straight to the live unit running at the device rate.
//
// Sixty seconds, which is not generous. On 78 rpm tango transfers a line the prominence
// route can see turns up inside 15 s, but one sitting down in the rumble — 7.8 dB
// prominent, well under the 16 dB threshold — only reaches the coherence route at 43 s,
// because that ratio accumulates over kCohWindowSec. Those are exactly the transfers
// this is worth doing for, so the window has to cover them.
//
static int sScoutHumLines(NSURL *fileURL, float sensitivity, float searchTo,
                          const std::atomic<long> *generationNow, long generation,
                          dehum::LineReport *out, int max)
{
    static const double        sSecondsToRead = 60.0;
    static const AVAudioFrameCount sBlockFrames = 4096;

    NSError *error = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:fileURL error:&error];
    if (!file) return 0;

    AVAudioFormat *format = [file processingFormat];   // always float32, non-interleaved
    double    rate     = [format sampleRate];
    AVAudioChannelCount chans = [format channelCount];

    if (rate <= 0 || chans < 1) return 0;

    dehum::Params p = dehum::Params::defaults();
    p.sensitivity = sensitivity;
    p.searchTo    = searchTo;
    p.frequency   = 0;
    p.sanitize();

    dehum::Config cfg;
    cfg.compute(p, rate);

    dehum::Channel channel;
    channel.configure(cfg);

    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sBlockFrames];
    if (!buffer) return 0;

    // Hum is common mode, so one summed channel finds it for half the work
    std::vector<float> mono(sBlockFrames);

    SInt64 wanted = (SInt64)(sSecondsToRead * rate);
    SInt64 read   = 0;

    {
        dehum::scoped_flush_denormals ftz;

        while (read < wanted) {
            AVAudioFrameCount want = sBlockFrames;
            if ((SInt64)want > (wanted - read)) want = (AVAudioFrameCount)(wanted - read);

            if (![file readIntoBuffer:buffer frameCount:want error:&error]) break;

            AVAudioFrameCount frames = [buffer frameLength];
            if (frames == 0) break;

            // Another track started; whatever this finds is already stale
            if (generationNow->load(std::memory_order_relaxed) != generation) return 0;

            const float * const *channels = [buffer floatChannelData];
            if (!channels) break;

            for (AVAudioFrameCount f = 0; f < frames; f++) mono[f] = 0;

            for (AVAudioChannelCount c = 0; c < chans; c++) {
                const float *source = channels[c];
                if (!source) continue;

                for (AVAudioFrameCount f = 0; f < frames; f++) mono[f] += source[f];
            }

            float scale = 1.0f / (float)chans;
            for (AVAudioFrameCount f = 0; f < frames; f++) mono[f] *= scale;

            channel.process(mono.data(), frames, 1);
            read += frames;
        }
    }

    int count = 0;
    channel.report(out, max, &count);

    return count;
}


@interface TDDehumUnit : TDRestorationUnit
@end


@implementation TDDehumUnit {
    TDDehumDSP *_dsp;
}

- (NSArray<AUParameter *> *) createParameters
{
    dehum::Params defaults = dehum::Params::defaults();

    // Frequency and Rumble both take zero as an off position rather than as a
    // frequency: 0 Hz means detect automatically, and no high-pass at all.
    return @[
        sMakeParameter(@"sensitivity", @"Sensitivity", TDDehumParamSensitivity, 0,   1,   defaults.sensitivity, kAudioUnitParameterUnit_Generic),
        sMakeParameter(@"bandwidth",   @"Bandwidth",   TDDehumParamBandwidth,   0.1, 5,   defaults.bandwidth,   kAudioUnitParameterUnit_Hertz),
        sMakeParameter(@"searchTo",    @"Search To",   TDDehumParamSearchTo,    40,  dehum::kSearchCeil,   defaults.searchTo,  kAudioUnitParameterUnit_Hertz),
        sMakeParameter(@"harmonics",   @"Harmonics",   TDDehumParamHarmonics,   1,   dehum::kMaxHarmonics, defaults.harmonics, kAudioUnitParameterUnit_Indexed),
        sMakeParameter(@"frequency",   @"Frequency",   TDDehumParamFrequency,   0,   500, defaults.frequency,   kAudioUnitParameterUnit_Hertz),
        sMakeParameter(@"rumble",      @"Rumble",      TDDehumParamRumbleHz,    0,   200, defaults.rumbleHz,    kAudioUnitParameterUnit_Hertz),
        sMakeParameter(@"dryWet",      @"Dry/Wet",     TDDehumParamDryWet,      0,   1,   defaults.dryWet,      kAudioUnitParameterUnit_Generic)
    ];
}


- (void) createDSP  { _dsp = new TDDehumDSP(); }
- (void) destroyDSP { delete _dsp; _dsp = NULL; }


- (void) configureDSPWithSampleRate:(double)sampleRate channels:(int)channels
{
    _dsp->restart(sampleRate, channels);
    _dsp->update([self state]);
}


- (void) td_forgetTrack
{
    // Whatever the last record's hum was, it is not this one's
    _dsp->pendingReady.store(false, std::memory_order_relaxed);
    _dsp->forgetPending.store(true, std::memory_order_relaxed);
    _dsp->scoutGeneration.fetch_add(1, std::memory_order_relaxed);
}


- (void) td_scoutFileURL:(NSURL *)fileURL
{
    TDRestorationState *state = [self state];

    _dsp->pendingReady.store(false, std::memory_order_relaxed);
    _dsp->forgetPending.store(true, std::memory_order_relaxed);

    // A frequency the user pinned by hand is theirs, not ours to overwrite
    if (!fileURL || state->get(TDDehumParamFrequency) > 0) return;

    float sensitivity = state->get(TDDehumParamSensitivity);
    float searchTo    = state->get(TDDehumParamSearchTo);

    long generation = _dsp->scoutGeneration.fetch_add(1, std::memory_order_relaxed) + 1;

    TDDehumDSP *dsp = _dsp;

    // self is captured strongly on purpose: it keeps the DSP alive for the scout
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        (void)self;

        // A vector rather than an array so the inner block can capture it
        std::vector<dehum::LineReport> lines((size_t)dehum::kMaxLines);

        int count = sScoutHumLines(fileURL, sensitivity, searchTo,
                                   &dsp->scoutGeneration, generation,
                                   lines.data(), (int)dehum::kMaxLines);
        lines.resize((size_t)count);

        dispatch_async(dispatch_get_main_queue(), ^{
            (void)self;

            // A later track already started; its scout owns the lines now
            if (dsp->scoutGeneration.load(std::memory_order_relaxed) != generation) return;

            NSMutableArray *described = [NSMutableArray array];
            for (size_t i = 0; i < lines.size(); i++) {
                [described addObject:[NSString stringWithFormat:@"%.3f Hz (%s)",
                    lines[i].frequency, lines[i].viaCoherence ? "coherence" : "prominence"]];

                dsp->pendingLines[i] = lines[i];
            }

            os_log(sLog(), "scouted %{public}@: %{public}@", [fileURL lastPathComponent],
                [described count] ? [described componentsJoinedByString:@", "]
                                  : @"no line, leaving it to the detector");

            dsp->pendingCount = (int)lines.size();
            dsp->pendingReady.store(!lines.empty(), std::memory_order_release);
        });
    });
}


- (AUInternalRenderBlock) createRenderBlock
{
    TDDehumDSP         *dsp   = _dsp;
    TDRestorationState *state = [self state];

    return ^AUAudioUnitStatus(
        AudioUnitRenderActionFlags *actionFlags,
        const AudioTimeStamp       *timestamp,
        AUAudioFrameCount           frameCount,
        NSInteger                   outputBusNumber,
        AudioBufferList            *outputData,
        const AURenderEvent        *realtimeEventListHead,
        AURenderPullInputBlock      pullInputBlock)
    {
        if (!pullInputBlock) return kAudioUnitErr_NoConnection;

        AUAudioUnitStatus err = sPrepareBufferList(outputData, frameCount);
        if (err) return err;

        AudioUnitRenderActionFlags pullFlags = 0;
        err = pullInputBlock(&pullFlags, timestamp, frameCount, 0, outputData);
        if (err) return err;

        // The notch integrator runs a recursion towards zero, so denormals are
        // reachable and slow.
        dehum::scoped_flush_denormals ftz;

        dsp->update(state);
        dsp->process(outputData, frameCount);

        return noErr;
    };
}

@end


#pragma mark - Registration and entry points

static AudioComponentDescription sDescription(OSType subType)
{
    AudioComponentDescription acd = {0};

    acd.componentType         = kAudioUnitType_Effect;
    acd.componentSubType      = subType;
    acd.componentManufacturer = TDRestorationManufacturer;
    acd.componentFlags        = 0;
    acd.componentFlagsMask    = 0;

    return acd;
}


BOOL TDRestorationRegister(void)
{
    static dispatch_once_t onceToken;
    static BOOL available = NO;

    dispatch_once(&onceToken, ^{
        AudioComponentDescription acd = sDescription(TDDeclickSubType);
        [AUAudioUnit registerSubclass: [TDDeclickUnit class]
               asComponentDescription: acd
                                 name: @"TangoDisplay: Declick"
                              version: 1];

        acd = sDescription(TDDehumSubType);
        [AUAudioUnit registerSubclass: [TDDehumUnit class]
               asComponentDescription: acd
                                 name: @"TangoDisplay: Dehum"
                              version: 1];

        // registerSubclass: publishes through AudioComponentRegister, which makes the
        // unit visible to AudioComponentFindNext in this process. It is not guaranteed
        // to reach AVAudioUnitComponentManager, which is why the host instantiates by
        // description rather than through the plugin picker. Confirm it took.
        AudioComponentDescription declick = sDescription(TDDeclickSubType);
        AudioComponentDescription dehum   = sDescription(TDDehumSubType);

        available = (AudioComponentFindNext(NULL, &declick) != NULL) &&
                    (AudioComponentFindNext(NULL, &dehum)   != NULL);

        if (!available) {
            os_log_error(sLog(), "component registration did not take; restoration unavailable");
        }
    });

    return available;
}


void TDRestorationForgetTrack(AUAudioUnit *unit)
{
    if ([unit conformsToProtocol:@protocol(TDTrackScoped)]) {
        [(id<TDTrackScoped>)unit td_forgetTrack];
    }
}


void TDRestorationScout(AUAudioUnit *unit, NSURL *fileURL)
{
    if ([unit respondsToSelector:@selector(td_scoutFileURL:)]) {
        [(id<TDTrackScoped>)unit td_scoutFileURL:fileURL];
    }
}


#pragma mark - Self test

// Deterministic noise. rand() would make the test depend on process state.
static double sNoise(uint32_t *seed)
{
    *seed = (*seed * 1664525u) + 1013904223u;
    return ((double)(*seed >> 8) / 8388608.0) - 1.0;   // -1 … 1
}


// Magnitude of `signal` at `freq`, over the second half only, so a converging notch is
// judged on where it ended up rather than on its acquisition.
static double sMagnitudeAt(const std::vector<float> &signal, double freq, double rate)
{
    size_t from = signal.size() / 2;
    double re = 0, im = 0;

    for (size_t i = from; i < signal.size(); i++) {
        double theta = 2.0 * M_PI * freq * (double)i / rate;
        re += signal[i] * cos(theta);
        im -= signal[i] * sin(theta);
    }

    double n = (double)(signal.size() - from);
    return sqrt(re * re + im * im) / n;
}


static double sRMS(const std::vector<float> &a, const std::vector<float> &b)
{
    double sum = 0;
    for (size_t i = 0; i < a.size(); i++) {
        double d = (double)a[i] - (double)b[i];
        sum += d * d;
    }
    return sqrt(sum / (double)a.size());
}


// 1 = declick failed, 2 = dehum failed.
int TDRestorationSelfTest(void)
{
    const double rate = 44100.0;
    int result = 0;

    // --- Declick: 220 Hz sine with impulses injected at known positions -------------
    {
        declick::scoped_flush_denormals ftz;

        const size_t n = (size_t)(2.0 * rate);

        std::vector<float> clean(n), dirty(n), repaired(n);
        for (size_t i = 0; i < n; i++) {
            clean[i] = (float)(0.5 * sin(2.0 * M_PI * 220.0 * (double)i / rate));
        }

        dirty = clean;
        for (int k = 0; k < 20; k++) {
            size_t at = (size_t)(2000 + k * 4000);
            if (at < n) dirty[at] += (k % 2 ? 2.5f : -2.5f);
        }

        declick::Params p = declick::Params::defaults();
        // Repair depth 1 rather than the default 0. At 0 the core deliberately
        // subtracts only the calibrated fraction of each click (wienerMax, 0.45) —
        // the setting that adds the least error of its own on real material, but one
        // that leaves half the click behind by design and so gives the test no margin.
        // 1 replaces the damaged samples outright, which is the same detect-and-
        // interpolate path with an unambiguous answer.
        p.depth = 1.0f;
        p.sanitize();

        declick::Config cfg;
        cfg.compute(p, rate);

        declick::Channel ch;
        ch.configure(cfg);

        // Whole file in one go: push everything, drain the tail, take n back. Output
        // frame i is then input frame i, so no latency compensation is needed here.
        ch.push(dirty.data(), n, 1);
        ch.drain();

        size_t got = std::min(ch.available(), n);
        ch.pull(repaired.data(), got, 1);
        for (size_t i = got; i < n; i++) repaired[i] = dirty[i];

        double before = sRMS(dirty, clean);
        double after  = sRMS(repaired, clean);

        // > 6 dB better, and it must actually have flagged something
        bool quieter = (after > 0) && (before / after > 2.0);
        if (!quieter || ch.repairedSamples() == 0) result |= 1;
    }

    // --- Dehum: 50 Hz tone in noise, notch pinned so nothing waits on the detector ---
    {
        dehum::scoped_flush_denormals ftz;

        const size_t n = (size_t)(10.0 * rate);

        std::vector<float> signal(n);
        uint32_t seed = 12345;
        for (size_t i = 0; i < n; i++) {
            double tone = 0.2 * sin(2.0 * M_PI * 50.0 * (double)i / rate);
            signal[i] = (float)(tone + 0.02 * sNoise(&seed));
        }

        double before = sMagnitudeAt(signal, 50.0, rate);

        dehum::Params p = dehum::Params::defaults();
        p.frequency = 50.0f;   // syncManual() engages immediately
        p.rumbleHz  = 0.0f;    // isolate the notch from the high-pass
        p.sanitize();

        dehum::Config cfg;
        cfg.compute(p, rate);

        dehum::Channel ch;
        ch.configure(cfg);
        ch.process(signal.data(), n, 1);

        double after = sMagnitudeAt(signal, 50.0, rate);

        // > 20 dB down
        if (!(after > 0) || (before / after < 10.0)) result |= 2;
    }

    return result;
}
