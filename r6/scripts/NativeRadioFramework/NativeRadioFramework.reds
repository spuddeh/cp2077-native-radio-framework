// ======================================================================================
// Mod Name: Native Radio Framework
// Author: Spuddeh
// Description: Registers each declared station's membership and content with the audio metadata.
// File Version: 0.1.0
// Credits: RED4ext by WopsS. AudioXL by DigitalVixen.
// ======================================================================================

module NativeRadioFramework

@if(ModuleExists("RedLogger"))
import RedLogger.*

@if(ModuleExists("RedLogger"))
public func NRFLog(msg: String) -> Void {
  RedLog.Append("NativeRadioFramework", msg);
}

@if(!ModuleExists("RedLogger"))
public func NRFLog(msg: String) -> Void {}

// Supplied by the plugin, which reads the station manifests. The list is declared once, in the
// manifest, and read from here - never restated in script.
public native func NRF_StationCount() -> Int32;
public native func NRF_StationName(index: Int32) -> CName;
public native func NRF_StationTrackCount(index: Int32) -> Int32;
public native func NRF_StationTrack(index: Int32, track: Int32) -> CName;

// A station needs three things and the plugin supplies the first. This adds the other two as the
// cooked audio metadata loads:
//
//   membership  its name in audioRadioStationMetadataMap.radioStations, which is what makes the
//               engine construct the station at all
//   content     an audioRadioStationMetadata entry carrying its track list
//
// Order matters only in that the plugin patches the roster at load, long before this runs. A
// station that gains membership without identity kills every radio in the game.
public class NativeRadioFramework extends ScriptableService {

  private let m_tokens: array<ref<ResourceToken>>;
  private let m_done: Bool;

  private cb func OnLoad() {
    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Resource/Load", this, n"OnCookedMetadata")
      .AddTarget(ResourceTarget.Path(r"base\\sound\\metadata\\cooked_metadata.audio_metadata"));

    // Resource/Load only fires while a resource is loading, so it never arrives for one another
    // mod has already pulled in. Ask the depot as well, and make the work safe to run twice.
    let cooked = GameInstance.GetResourceDepot()
      .LoadResource(r"base\\sound\\metadata\\cooked_metadata.audio_metadata");
    if IsDefined(cooked) {
      ArrayPush(this.m_tokens, cooked);
      cooked.RegisterCallback(this, n"OnCookedReady");
    }
  }

  private cb func OnCookedMetadata(event: ref<ResourceEvent>) {
    this.Register(event.GetResource() as audioCookedMetadataResource);
  }

  private cb func OnCookedReady(token: ref<ResourceToken>) {
    this.Register(token.GetResource() as audioCookedMetadataResource);
  }

  private func Register(cooked: ref<audioCookedMetadataResource>) -> Void {
    if !IsDefined(cooked) || this.m_done { return; }
    this.m_done = true;

    let count: Int32 = NRF_StationCount();
    if count <= 0 {
      NRFLog("no stations registered - either none are installed, or the roster was not patched");
      return;
    }

    let map: ref<audioRadioStationMetadataMap>;
    for entry in cooked.entries {
      let candidate = entry as audioRadioStationMetadataMap;
      if IsDefined(candidate) {
        map = candidate;
        break;
      }
    }
    if !IsDefined(map) {
      NRFLog("no station map in this metadata resource - nothing registered");
      return;
    }

    let i: Int32 = 0;
    while i < count {
      this.RegisterOne(cooked, map, i);
      i += 1;
    }
  }

  private func RegisterOne(cooked: ref<audioCookedMetadataResource>,
                           map: ref<audioRadioStationMetadataMap>, index: Int32) -> Void {
    let name: CName = NRF_StationName(index);
    if !IsNameValid(name) { return; }

    if IsDefined(this.Find(cooked, name)) {
      NRFLog(s"\(name) is already defined - left alone");
      return;
    }

    let station = new audioRadioStationMetadata();
    station.name = name;
    station.speaker = audioRadioSpeakerType.None;

    let tracks: Int32 = NRF_StationTrackCount(index);
    let t: Int32 = 0;
    while t < tracks {
      let event: CName = NRF_StationTrack(index, t);
      if IsNameValid(event) {
        ArrayPush(station.tracks, event);
      }
      t += 1;
    }

    if ArraySize(station.tracks) == 0 {
      NRFLog(s"\(name) has no usable tracks - not registered");
      return;
    }

    ArrayPush(cooked.entries, station);
    if !ArrayContains(map.radioStations, name) {
      ArrayPush(map.radioStations, name);
    }

    NRFLog(s"registered \(name): \(ArraySize(station.tracks)) track(s), map now lists \(ArraySize(map.radioStations))");
  }

  private func Find(cooked: ref<audioCookedMetadataResource>, name: CName) -> ref<audioRadioStationMetadata> {
    for entry in cooked.entries {
      let station = entry as audioRadioStationMetadata;
      if IsDefined(station) && Equals(station.name, name) {
        return station;
      }
    }
    return null;
  }
}
