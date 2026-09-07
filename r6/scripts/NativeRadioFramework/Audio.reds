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

// Radio music follows the Vehicle Radio slider, which is the mixer vanilla stations use.
public class NRFAudio {

  @if(ModuleExists("AudioXL"))
  public final static func Register(event: CName, file: String) -> Bool {
    // Streamed rather than held in memory: a station is tens of minutes of audio.
    return AudioXLNative.RegisterSoundEx(event, n"axl_radio_2d", file, 1.0, 0.0, 0.0,
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
