// ======================================================================================
// Mod Name: Native Radio Framework
// Author: Spuddeh
// Description: The AudioXL bridge - the one place this framework talks about sound.
// File Version: 0.2.0
// Credits: AudioXL by DigitalVixen.
// ======================================================================================
//
// **This framework does not decode, stream or mix anything.** AudioXL registers a file and becomes
// the authority on it: the length the station schedules against, and the Wwise id the engine posts.
// Neither is written in a station manifest, so neither can disagree with the file on disk.
//
// Without AudioXL every call here answers "nothing registered", so a station with file-backed
// tracks reports no playable tracks and is skipped. The rest of the framework still loads.

module NativeRadioFramework

@if(ModuleExists("AudioXL"))
import AudioXL.*

// **`mod_sfx_radio` is the GAME's own radio routing, and a station must use it.** An `axl_*` type is
// a 2D sound on a mixer: nothing owns it, so the radio system cannot stop it, a car cannot take it
// over from the Radioport, and it is audible at a world device whether or not that device plays.
// A station is a voice on the radio's own emitter, never a sound played alongside it.
public class NRFAudio {

  @if(ModuleExists("AudioXL"))
  public final static func Register(event: CName, file: String) -> Bool {
    // Streamed rather than held in memory: a station is tens of minutes of audio.
    return AudioXLNative.RegisterSoundEx(event, n"mod_sfx_radio", file, 1.0, 0.0, 0.0,
                                         false, 0.0, 0.0, 0.0, 0.0, 0.0, true);
  }

  @if(!ModuleExists("AudioXL"))
  public final static func Register(event: CName, file: String) -> Bool {
    return false;
  }

  @if(ModuleExists("AudioXL"))
  public final static func Has(event: CName) -> Bool {
    return AudioXLNative.Has(event);
  }

  @if(!ModuleExists("AudioXL"))
  public final static func Has(event: CName) -> Bool {
    return false;
  }

  @if(ModuleExists("AudioXL"))
  public final static func Duration(event: CName) -> Float {
    return AudioXLNative.Duration(event);
  }

  @if(!ModuleExists("AudioXL"))
  public final static func Duration(event: CName) -> Float {
    return 0.0;
  }

  @if(ModuleExists("AudioXL"))
  public final static func WwiseId(event: CName) -> Uint32 {
    return AudioXLNative.WwiseId(event);
  }

  @if(!ModuleExists("AudioXL"))
  public final static func WwiseId(event: CName) -> Uint32 {
    return 0u;
  }

  @if(ModuleExists("AudioXL"))
  public final static func Available() -> Bool {
    return AudioXLNative.Available();
  }

  @if(!ModuleExists("AudioXL"))
  public final static func Available() -> Bool {
    return false;
  }
}
