//
//  TDRestoration.h
//  In-process Audio Units wrapping the ShellacFilters declick and dehum DSP cores
//  from https://github.com/shaforostoff/shellacfilters (MIT).
//
//  The wrapper is adapted from EmbraceNG's RestorationAudioUnit.mm
//  (c) 2024 Ricci Adams, MIT / 1-clause BSD.
//
//  Sources/TangoDisplayObjC/shellac/*.{h,cpp} are verbatim copies of the portable
//  cores — update them by copying from upstream, not by editing.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

extern const OSType TDRestorationManufacturer;   // 'TgDs'
extern const OSType TDDeclickSubType;            // 'dclk'
extern const OSType TDDehumSubType;              // 'dhum'

/// Parameter addresses, in the order the units publish them. Swift writes values
/// through -[AUParameterTree parameterWithAddress:], so these are the contract.
typedef NS_ENUM(AUParameterAddress, TDDeclickParam) {
    TDDeclickParamSensitivity = 0,   // 0…1
    TDDeclickParamExtent      = 1,   // 0…1
    TDDeclickParamMaxLengthMs = 2,   // 0.2…20 ms
    TDDeclickParamDepth       = 3,   // 0…1
    TDDeclickParamPasses      = 4,   // 1…3
    TDDeclickParamOrder       = 5,   // 8…256
    TDDeclickParamDryWet      = 6    // 0…1
};

typedef NS_ENUM(AUParameterAddress, TDDehumParam) {
    TDDehumParamSensitivity = 0,     // 0…1
    TDDehumParamBandwidth   = 1,     // 0.1…5 Hz
    TDDehumParamSearchTo    = 2,     // 40…500 Hz
    TDDehumParamHarmonics   = 3,     // 1…8
    TDDehumParamFrequency   = 4,     // 0 = detect automatically, else Hz
    TDDehumParamRumbleHz    = 5,     // 0 = off, else high-pass corner in Hz
    TDDehumParamDryWet      = 6      // 0…1
};

#ifdef __cplusplus
extern "C" {
#endif

/// Registers both units with AudioComponent so they can be instantiated by
/// description. Idempotent. Returns NO if either component cannot be found
/// afterwards, in which case the caller should carry on without restoration.
extern BOOL TDRestorationRegister(void);

/// A new record means a new hum and a fresh pipeline: drops whatever either core
/// learned from the previous track. Safe to call with a nil or foreign unit.
extern void TDRestorationForgetTrack(AUAudioUnit * _Nullable unit);

/// Reads the opening of `fileURL` off-thread and pre-seeds dehum's line detector
/// with whatever it finds, so a track does not have to spend the acquisition time
/// (9 s at best, 43 s for a line only the coherence route can see) with the hum
/// still audible. No-op unless `unit` is the dehum unit, and skipped when the user
/// has pinned a frequency by hand. Supersedes any scout still in flight.
extern void TDRestorationScout(AUAudioUnit * _Nullable unit, NSURL * _Nullable fileURL);

/// Runs both cores over synthetic signals with known answers. Returns 0 on pass,
/// otherwise a bitmask: 1 = declick did not repair, 2 = dehum did not notch.
/// Exercises the SSE2 path on x86_64 and the scalar path on arm64.
extern int TDRestorationSelfTest(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
