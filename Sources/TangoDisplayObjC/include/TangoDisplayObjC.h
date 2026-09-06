#import <AVFAudio/AVFAudio.h>

// Umbrella header: SwiftPM exposes this module through this file alone, so anything
// Swift needs to see has to be reachable from here.
#import "TDRestoration.h"

/// Calls -[AVAudioEngine connect:to:format:] inside @try/@catch.
/// Returns YES on success. On failure, *outReason is set to the exception reason.
BOOL TDTryAudioEngineConnect(AVAudioEngine *engine,
                              AVAudioNode   *source,
                              AVAudioNode   *destination,
                              AVAudioFormat *format,
                              NSString     **outReason);
