// ======================================================================================
// Mod Name: Native Radio Framework
// Author: Spuddeh
// Description: Builds each declared station out of the engine's own radio systems.
// File Version: 0.2.0
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
public native func NRF_StationKey(index: Int32) -> CName;
public native func NRF_StationDisplayName(index: Int32) -> String;
public native func NRF_StationIcon(index: Int32) -> String;
public native func NRF_StationAtlas(index: Int32) -> String;
public native func NRF_StationSpeaker(index: Int32) -> String;
public native func NRF_StationTrackCount(index: Int32) -> Int32;
public native func NRF_StationTrack(index: Int32, track: Int32) -> CName;
public native func NRF_StationTrackKey(index: Int32, track: Int32) -> CName;
public native func NRF_StationTrackFile(index: Int32, track: Int32) -> String;
public native func NRF_StationTrackTitle(index: Int32, track: Int32) -> String;

// A station is assembled out of the systems the game already has, in this order:
//
//   identity      its CName in the engine roster              the plugin, at load
//   audio         AudioXL registers each track's file          RegisterAudio
//   membership    its name in radioStations                    RegisterStation
//   content       an audioRadioStationMetadata with tracks     RegisterStation
//   titles        an audioRadioTrack row per track             RegisterStation
//   text          onscreens entries for the name and titles    RegisterText
//
// **Every label the game shows is a localization KEY, never the text.** The name table the plugin
// patches holds one, and so does every audioRadioTrack. A station's key is minted here and the text
// registered against it, so the UI resolves a custom station exactly as it resolves a vanilla one.
// Raw text in those slots is what makes a label vanish and the station selector match nothing.
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

// AudioXL answers only once its registry is ready, several seconds after the audio metadata
// loads. This carries the retry.
public class NRFPoll extends DelayCallback {
  public let service: wref<NativeRadioFramework>;

  public func Call() -> Void {
    if IsDefined(this.service) {
      this.service.Poll();
    }
  }
}

public class NativeRadioFramework extends ScriptableService {

  private let m_tokens: array<ref<ResourceToken>>;
  private let m_events: ref<audioAudioEventArray>;
  private let m_audioDone: Bool;
  private let m_cookedDone: Bool;
  private let m_eventsDone: Bool;
  private let m_textDone: Bool;
  private let m_polls: Int32;

  private cb func OnLoad() {
    let cb = GameInstance.GetCallbackSystem();

    cb.RegisterCallback(n"Resource/Load", this, n"OnCookedMetadata")
      .AddTarget(ResourceTarget.Path(r"base\\sound\\metadata\\cooked_metadata.audio_metadata"));
    cb.RegisterCallback(n"Resource/Load", this, n"OnEventsMetadata")
      .AddTarget(ResourceTarget.Path(r"base\\sound\\event\\eventsmetadata.json"));
    cb.RegisterCallback(n"Resource/Load", this, n"OnOnScreens")
      .AddTarget(ResourceTarget.Path(r"base\\localization\\en-us\\onscreens\\onscreens.json"));

    // Resource/Load only fires while a resource is loading, so it never arrives for one another
    // mod has already pulled in. Ask the depot as well, and make the work safe to run twice.
    let depot = GameInstance.GetResourceDepot();
    this.Watch(depot, r"base\\sound\\metadata\\cooked_metadata.audio_metadata", n"OnCookedReady");
    this.Watch(depot, r"base\\sound\\event\\eventsmetadata.json", n"OnEventsReady");
    this.Watch(depot, r"base\\localization\\en-us\\onscreens\\onscreens.json", n"OnOnScreensReady");
  }

  private func Watch(depot: ref<ResourceDepot>, path: ResRef, callback: CName) -> Void {
    let token = depot.LoadResource(path);
    if IsDefined(token) {
      ArrayPush(this.m_tokens, token);
      token.RegisterCallback(this, callback);
    }
  }

  // --- audio --------------------------------------------------------------------------------------
  // AudioXL owns sound. It takes the file, and it reports the length and the Wwise id, so neither
  // has to be written into a manifest where it could disagree with the file.

  private func RegisterAudio() -> Void {
    if this.m_audioDone { return; }
    this.m_audioDone = true;

    let registered: Int32 = 0;
    let station: Int32 = 0;
    let count: Int32 = NRF_StationCount();
    while station < count {
      let tracks: Int32 = NRF_StationTrackCount(station);
      let t: Int32 = 0;
      while t < tracks {
        let event: CName = NRF_StationTrack(station, t);
        let file: String = NRF_StationTrackFile(station, t);
        if IsNameValid(event) && StrLen(file) > 0 && !NRFAudio.Has(event) {
          if NRFAudio.Register(event, file) {
            registered += 1;
          } else {
            NRFLog(s"AudioXL refused \(event) - \(file)");
          }
        }
        t += 1;
      }
      station += 1;
    }
    NRFLog(s"registered \(registered) track(s) with AudioXL");
  }

  // --- the audio event table ------------------------------------------------------------------------
  // An event present in the registry but absent from this table cannot be posted by name, and fails
  // silently. The duration here is what the station schedules the next track against.

  private cb func OnEventsMetadata(event: ref<ResourceEvent>) {
    this.RegisterEvents(event.GetResource() as JsonResource);
  }

  private cb func OnEventsReady(token: ref<ResourceToken>) {
    this.RegisterEvents(token.GetResource() as JsonResource);
  }

  private func RegisterEvents(resource: ref<JsonResource>) -> Void {
    if !IsDefined(resource) || IsDefined(this.m_events) { return; }
    let events = resource.root as audioAudioEventArray;
    if !IsDefined(events) { return; }

    // The rows cannot be written yet. AudioXL reports a length only once its registry is ready,
    // and that happens several seconds after this resource loads, so the array is kept and filled
    // in as soon as it can answer. A row written now would carry a zero duration, and a station
    // schedules its next track against that.
    this.m_events = events;
    this.Poll();
  }

  // Runs until AudioXL can answer, then registers the audio and writes the event rows. Bounded, so
  // a missing or broken AudioXL costs a minute of polling rather than a permanent timer.
  public func Poll() -> Void {
    if this.m_eventsDone { return; }

    if NRFAudio.Available() {
      this.RegisterAudio();
      if this.WriteEvents() {
        return;
      }
    }

    this.m_polls += 1;
    if this.m_polls > 120 {
      NRFLog("AudioXL never became ready - no track has a duration, so no station can play");
      return;
    }

    let delay = GameInstance.GetDelaySystem(GetGameInstance());
    if !IsDefined(delay) { return; }
    let again = new NRFPoll();
    again.service = this;
    delay.DelayCallback(again, 0.5);
  }

  private func WriteEvents() -> Bool {
    let added: Int32 = 0;
    let missing: Int32 = 0;
    let station: Int32 = 0;
    let count: Int32 = NRF_StationCount();
    while station < count {
      let tracks: Int32 = NRF_StationTrackCount(station);
      let t: Int32 = 0;
      while t < tracks {
        let name: CName = NRF_StationTrack(station, t);
        let duration: Float = NRFAudio.Duration(name);
        if duration <= 0.0 {
          missing += 1;
        } else {
          if !this.HasEvent(this.m_events, name) {
            let row: audioAudioEventMetadataArrayElement;
            row.redId = name;
            row.wwiseId = NRFAudio.WwiseId(name);
            row.isLooping = false;
            row.maxAttenuation = 0.0;
            row.minDuration = duration;
            row.maxDuration = duration;
            ArrayPush(this.m_events.events, row);
            added += 1;
          }
        }
        t += 1;
      }
      station += 1;
    }

    // Every track answering is the only proof the registry finished. Half an answer means it is
    // still decoding, so this returns and the poll comes back.
    if missing > 0 {
      return false;
    }
    this.m_eventsDone = true;
    NRFLog(s"registered \(added) event(s) in the audio event table after \(this.m_polls) poll(s)");
    return true;
  }

  private func HasEvent(events: ref<audioAudioEventArray>, name: CName) -> Bool {
    let i: Int32 = 0;
    while i < ArraySize(events.events) {
      if Equals(events.events[i].redId, name) { return true; }
      i += 1;
    }
    return false;
  }

  // --- membership, content and titles ----------------------------------------------------------------

  private cb func OnCookedMetadata(event: ref<ResourceEvent>) {
    this.Register(event.GetResource() as audioCookedMetadataResource);
  }

  private cb func OnCookedReady(token: ref<ResourceToken>) {
    this.Register(token.GetResource() as audioCookedMetadataResource);
  }

  private func Register(cooked: ref<audioCookedMetadataResource>) -> Void {
    if !IsDefined(cooked) || this.m_cookedDone { return; }

    let count: Int32 = NRF_StationCount();
    if count <= 0 {
      NRFLog("no stations registered - either none are installed, or the roster was not patched");
      return;
    }
    this.m_cookedDone = true;

    let map: ref<audioRadioStationMetadataMap>;
    let titles: ref<audioRadioTracksMetadata>;
    for entry in cooked.entries {
      let candidate = entry as audioRadioStationMetadataMap;
      if IsDefined(candidate) { map = candidate; }
      let trackTable = entry as audioRadioTracksMetadata;
      if IsDefined(trackTable) { titles = trackTable; }
    }
    if !IsDefined(map) {
      NRFLog("no station map in this metadata resource - nothing registered");
      return;
    }

    let i: Int32 = 0;
    while i < count {
      this.RegisterStation(cooked, map, titles, i);
      i += 1;
    }
  }

  private func RegisterStation(cooked: ref<audioCookedMetadataResource>,
                               map: ref<audioRadioStationMetadataMap>,
                               titles: ref<audioRadioTracksMetadata>, index: Int32) -> Void {
    let name: CName = NRF_StationName(index);
    if !IsNameValid(name) { return; }

    if IsDefined(this.Find(cooked, name)) {
      NRFLog(s"\(name) is already defined - left alone");
      return;
    }

    let station = new audioRadioStationMetadata();
    station.name = name;
    // The DJ, and `None` is the default - a station with no speaker plays. Vanilla names one on
    // every station, so a station mod that wants one asks for it by name in its manifest.
    station.speaker = NRFSpeaker(NRF_StationSpeaker(index));

    let tracks: Int32 = NRF_StationTrackCount(index);
    let t: Int32 = 0;
    while t < tracks {
      let event: CName = NRF_StationTrack(index, t);
      if IsNameValid(event) {
        ArrayPush(station.tracks, event);
        this.AddTitle(titles, index, t, event);
      }
      t += 1;
    }

    if ArraySize(station.tracks) == 0 {
      NRFLog(s"\(name) lists no tracks - not registered");
      return;
    }

    ArrayPush(cooked.entries, station);
    if !ArrayContains(map.radioStations, name) {
      ArrayPush(map.radioStations, name);
    }

    NRFLog(s"registered \(name): \(ArraySize(station.tracks)) track(s), map now lists \(ArraySize(map.radioStations))");
  }

  // The row the dashboard and the radio wheel read the song title from. `localizationKey` is a key,
  // and RegisterText is what makes it resolve.
  private func AddTitle(titles: ref<audioRadioTracksMetadata>, station: Int32, track: Int32,
                        event: CName) -> Void {
    if !IsDefined(titles) || StrLen(NRF_StationTrackTitle(station, track)) == 0 { return; }
    let i: Int32 = 0;
    while i < ArraySize(titles.radioTracks) {
      if Equals(titles.radioTracks[i].trackEventName, event) { return; }
      i += 1;
    }
    let row: audioRadioTrack;
    row.trackEventName = event;
    row.localizationKey = NRF_StationTrackKey(station, track);
    row.isStreamingFriendly = true;
    ArrayPush(titles.radioTracks, row);
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

  // --- the text behind every key -----------------------------------------------------------------------
  // onscreens.json is a JsonResource holding localizationPersistenceOnScreenEntries, so a station's
  // name and its song titles are registered the same way its audio events are: by adding rows as the
  // resource loads. No archive, and no ArchiveXL dependency.

  private cb func OnOnScreens(event: ref<ResourceEvent>) {
    this.RegisterText(event.GetResource() as JsonResource);
  }

  private cb func OnOnScreensReady(token: ref<ResourceToken>) {
    this.RegisterText(token.GetResource() as JsonResource);
  }

  private func RegisterText(resource: ref<JsonResource>) -> Void {
    if !IsDefined(resource) || this.m_textDone { return; }
    let screens = resource.root as localizationPersistenceOnScreenEntries;
    if !IsDefined(screens) { return; }
    this.m_textDone = true;

    let added: Int32 = 0;
    let station: Int32 = 0;
    let count: Int32 = NRF_StationCount();
    while station < count {
      added += this.AddText(screens, NRF_StationKey(station), NRF_StationDisplayName(station));
      let tracks: Int32 = NRF_StationTrackCount(station);
      let t: Int32 = 0;
      while t < tracks {
        added += this.AddText(screens, NRF_StationTrackKey(station, t),
                              NRF_StationTrackTitle(station, t));
        t += 1;
      }
      station += 1;
    }
    NRFLog(s"registered \(added) string(s) in onscreens");
  }

  private func AddText(screens: ref<localizationPersistenceOnScreenEntries>, key: CName,
                       text: String) -> Int32 {
    if !IsNameValid(key) || StrLen(text) == 0 { return 0; }
    let row = new localizationPersistenceOnScreenEntry();
    row.primaryKey = 0ul;
    row.secondaryKey = NameToString(key);
    row.femaleVariant = text;
    ArrayPush(screens.entries, row);
    return 1;
  }
}
