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
public native func NRF_StationTrackDuration(index: Int32, track: Int32) -> Float;
public native func NRF_StationTrackWwiseId(index: Int32, track: Int32) -> Uint32;
public native func NRF_StationTrackTitle(index: Int32, track: Int32) -> String;
public native func NRF_StationRecord(index: Int32) -> String;
public native func NRF_StationSpeaker(index: Int32) -> String;

// A station needs three things and the plugin supplies the first. This adds the other two as the
// cooked audio metadata loads:
//
//   membership  its name in audioRadioStationMetadataMap.radioStations, which is what makes the
//               engine construct the station at all
//   content     an audioRadioStationMetadata entry carrying its track list
//
// Order matters only in that the plugin patches the roster at load, long before this runs. A
// station that gains membership without identity kills every radio in the game.
public func NRFSpeaker(name: String) -> audioRadioSpeakerType {
  switch name {
    case "MaximumMike": return audioRadioSpeakerType.MaximumMike;
    case "PoliceDispatch": return audioRadioSpeakerType.PoliceDispatch;
    case "Kurtz": return audioRadioSpeakerType.Kurtz;
    case "Ash": return audioRadioSpeakerType.Ash;
    case "Stanley": return audioRadioSpeakerType.Stanley;
  }
  return audioRadioSpeakerType.None;
}

public class NativeRadioFramework extends ScriptableService {

  private let m_tokens: array<ref<ResourceToken>>;
  private let m_done: Bool;
  private let m_eventsDone: Bool;

  private cb func OnLoad() {
    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Resource/Load", this, n"OnCookedMetadata")
      .AddTarget(ResourceTarget.Path(r"base\\sound\\metadata\\cooked_metadata.audio_metadata"));

    // Resource/Load only fires while a resource is loading, so it never arrives for one another
    // mod has already pulled in. Ask the depot as well, and make the work safe to run twice.
    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Resource/Load", this, n"OnEventsMetadata")
      .AddTarget(ResourceTarget.Path(r"base\\sound\\event\\eventsmetadata.json"));

    let depot = GameInstance.GetResourceDepot();

    let cooked = depot.LoadResource(r"base\\sound\\metadata\\cooked_metadata.audio_metadata");
    if IsDefined(cooked) {
      ArrayPush(this.m_tokens, cooked);
      cooked.RegisterCallback(this, n"OnCookedReady");
    }

    let events = depot.LoadResource(r"base\\sound\\event\\eventsmetadata.json");
    if IsDefined(events) {
      ArrayPush(this.m_tokens, events);
      events.RegisterCallback(this, n"OnEventsReady");
    }
  }

  private cb func OnEventsMetadata(event: ref<ResourceEvent>) {
    this.RegisterEvents(event.GetResource() as JsonResource);
  }

  private cb func OnEventsReady(token: ref<ResourceToken>) {
    this.RegisterEvents(token.GetResource() as JsonResource);
  }

  // An event present in a loaded bank but absent from this table cannot be posted by name, and
  // fails silently. The duration here is what the station schedules the next track against.
  private func RegisterEvents(resource: ref<JsonResource>) -> Void {
    if !IsDefined(resource) || this.m_eventsDone { return; }
    let events = resource.root as audioAudioEventArray;
    if !IsDefined(events) { return; }
    this.m_eventsDone = true;

    let added: Int32 = 0;
    let station: Int32 = 0;
    let count: Int32 = NRF_StationCount();
    while station < count {
      let tracks: Int32 = NRF_StationTrackCount(station);
      let t: Int32 = 0;
      while t < tracks {
        let name: CName = NRF_StationTrack(station, t);
        let duration: Float = NRF_StationTrackDuration(station, t);
        if IsNameValid(name) && duration > 0.0 && !this.HasEvent(events, name) {
          let row: audioAudioEventMetadataArrayElement;
          row.redId = name;
          row.wwiseId = NRF_StationTrackWwiseId(station, t);
          row.isLooping = false;
          row.maxAttenuation = 0.0;
          row.minDuration = duration;
          row.maxDuration = duration;
          ArrayPush(events.events, row);
          added += 1;
        }
        t += 1;
      }
      station += 1;
    }
    NRFLog(s"registered \(added) event(s) in the audio event table");
  }

  private func HasEvent(events: ref<audioAudioEventArray>, name: CName) -> Bool {
    let i: Int32 = 0;
    while i < ArraySize(events.events) {
      if Equals(events.events[i].redId, name) { return true; }
      i += 1;
    }
    return false;
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
    // The DJ, and `None` is the default - a station with no speaker plays. Vanilla names one on
    // every station (twelve are Stanley, Attitude Rock is Maximum Mike, Growl FM is Ash), so a
    // station mod that wants a DJ asks for one by name in its manifest.
    station.speaker = NRFSpeaker(NRF_StationSpeaker(index));

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
