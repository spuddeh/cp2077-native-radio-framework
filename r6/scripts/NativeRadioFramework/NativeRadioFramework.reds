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
public native func NRF_StationGain(index: Int32) -> Float;
public native func NRF_StationTrackCount(index: Int32) -> Int32;
public native func NRF_StationTrack(index: Int32, track: Int32) -> CName;
public native func NRF_StationTrackKey(index: Int32, track: Int32) -> CName;
public native func NRF_StationTrackFile(index: Int32, track: Int32) -> String;
public native func NRF_StationTrackTitle(index: Int32, track: Int32) -> String;
public native func NRF_StationTrackDuration(index: Int32, track: Int32) -> Float;
public native func NRF_StationKeyHash(index: Int32) -> Uint64;
public native func NRF_StationTrackKeyHash(index: Int32, track: Int32) -> Uint64;
public native func NRF_StationKeyHash64(index: Int32) -> Uint64;
public native func NRF_StationTrackKeyHash64(index: Int32, track: Int32) -> Uint64;

// A station is assembled out of the systems the game already has, in this order:
//
//   identity      its CName in the engine roster              the plugin, at load
//   length        each track's duration, from its file        the plugin, at load
//   schedule      an event row per track, with that length    RegisterEvents, as the table loads
//   membership    its name in radioStations                   Register, as the metadata loads
//   content       an audioRadioStationMetadata with tracks    Register, as the metadata loads
//   titles        an audioRadioTrack row per track            Register, as the metadata loads
//   text          onscreens entries for the name and titles   RegisterText, as the file loads
//   audio         AudioXL registers each track's file         RegisterAudio, whenever AudioXL can
//
// **The first seven happen while the resource they touch is LOADING, and nothing may delay them.**
// The engine builds its station set once, from those resources as they load. A station whose
// membership or event rows arrive afterwards is never constructed: its data is present, every log
// line reads as success, and every receiver is silent. Only the audio registration may wait,
// because AudioXL takes it whenever it is ready and the engine resolves the sound at play time.
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

// AudioXL takes a registration only once the engine's audio system exists. This carries the retry.
public class NRFPoll extends DelayCallback {
  public let service: wref<NativeRadioFramework>;

  public func Call() -> Void {
    if IsDefined(this.service) {
      this.service.Poll();
    }
  }
}

// A row AudioXL queued gets its level trim on a later pass. This carries that retry.
public class NRFGainPoll extends DelayCallback {
  public let service: wref<NativeRadioFramework>;

  public func Call() -> Void {
    if IsDefined(this.service) {
      this.service.ApplyGains();
    }
  }
}

public class NativeRadioFramework extends ScriptableService {

  private let m_tokens: array<ref<ResourceToken>>;
  private let m_audioDone: Bool;
  private let m_cookedDone: Bool;
  private let m_eventsDone: Bool;
  private let m_textDone: Bool;
  private let m_polls: Int32;
  private let m_gainPending: Bool;
  private let m_gainPolls: Int32;
  private let m_clock: ref<NRFStationClock>;

  private cb func OnLoad() {
    let cb = GameInstance.GetCallbackSystem();

    cb.RegisterCallback(n"Resource/Load", this, n"OnCookedMetadata")
      .AddTarget(ResourceTarget.Path(r"base\\sound\\metadata\\cooked_metadata.audio_metadata"));
    cb.RegisterCallback(n"Resource/Load", this, n"OnEventsMetadata")
      .AddTarget(ResourceTarget.Path(r"base\\sound\\event\\eventsmetadata.json"));
    cb.RegisterCallback(n"Resource/Load", this, n"OnOnScreens")
      .AddTarget(ResourceTarget.Path(r"base\\localization\\en-us\\onscreens\\onscreens.json"));

    // There is no DelaySystem before a session exists, so the retry cannot run on a timer alone.
    // A session becoming ready is both a retry opportunity and the point a timer starts working.
    cb.RegisterCallback(n"Session/Ready", this, n"OnSessionReady");

    // Resource/Load only fires while a resource is loading, so it never arrives for one another
    // mod has already pulled in. Ask the depot as well, and make the work safe to run twice.
    let depot = GameInstance.GetResourceDepot();
    this.Watch(depot, r"base\\sound\\metadata\\cooked_metadata.audio_metadata", n"OnCookedReady");
    this.Watch(depot, r"base\\sound\\event\\eventsmetadata.json", n"OnEventsReady");
    this.Watch(depot, r"base\\localization\\en-us\\onscreens\\onscreens.json", n"OnOnScreensReady");

    this.Poll();
  }

  private cb func OnSessionReady(event: ref<GameSessionEvent>) {
    this.Poll();
    if this.m_gainPending {
      this.ApplyGains();
    }
    if !IsDefined(this.m_clock) {
      this.m_clock = new NRFStationClock();
    }
    this.m_clock.Start();
  }

  // Where each station is in its own schedule. Null until a session has been ready once, because
  // the watch runs on the DelaySystem.
  public func Clock() -> ref<NRFStationClock> {
    return this.m_clock;
  }

  private func Watch(depot: ref<ResourceDepot>, path: ResRef, callback: CName) -> Void {
    let token = depot.LoadResource(path);
    if IsDefined(token) {
      ArrayPush(this.m_tokens, token);
      token.RegisterCallback(this, callback);
    }
  }

  // --- audio --------------------------------------------------------------------------------------
  // AudioXL owns sound. It takes the file and supplies the Wwise id; the track's length is the
  // plugin's, read from the file's headers, because it is needed before AudioXL can decode anything.

  private func RegisterAudio() -> Void {
    if this.m_audioDone { return; }
    this.m_audioDone = true;

    let registered: Int32 = 0;
    let station: Int32 = 0;
    let count: Int32 = NRF_StationCount();
    while station < count {
      let tracks: Int32 = NRF_StationTrackCount(station);
      let gain: Float = NRF_StationGain(station);
      let t: Int32 = 0;
      while t < tracks {
        let event: CName = NRF_StationTrack(station, t);
        let file: String = NRF_StationTrackFile(station, t);
        if IsNameValid(event) && StrLen(file) > 0 && !NRFAudio.Has(event) {
          if NRFAudio.Register(event, file) {
            registered += 1;
            if !NRFAudio.SetGain(event, gain) {
              this.m_gainPending = true;
            }
          } else {
            NRFLog(s"AudioXL refused \(event) - \(file)");
          }
        }
        t += 1;
      }
      station += 1;
    }
    NRFLog(s"registered \(registered) track(s) with AudioXL");
    if this.m_gainPending {
      this.ApplyGains();
    }
  }

  // A row AudioXL queued has no gain to set at registration time. Walk every track again until each
  // SetGain lands, bounded, so a row that never appears costs a few seconds rather than a timer.
  public func ApplyGains() -> Void {
    let failed: Int32 = 0;
    let station: Int32 = 0;
    let count: Int32 = NRF_StationCount();
    while station < count {
      let tracks: Int32 = NRF_StationTrackCount(station);
      let gain: Float = NRF_StationGain(station);
      let t: Int32 = 0;
      while t < tracks {
        let event: CName = NRF_StationTrack(station, t);
        if IsNameValid(event) && !NRFAudio.SetGain(event, gain) {
          failed += 1;
        }
        t += 1;
      }
      station += 1;
    }
    if failed == 0 {
      this.m_gainPending = false;
      NRFLog("level trim applied to every track");
      return;
    }
    this.m_gainPolls += 1;
    if this.m_gainPolls > 20 {
      NRFLog(s"\(failed) track(s) never got a row in AudioXL, so their level trim was not applied");
      this.m_gainPending = false;
      return;
    }
    // AudioXL's Available() is the plugin, not the engine's audio system, so the first pass runs
    // before any row exists and before a session has a DelaySystem. Session/Ready calls back in.
    let delay = GameInstance.GetDelaySystem(GetGameInstance());
    if !IsDefined(delay) {
      NRFLog(s"\(failed) track(s) have no row yet - level trim deferred to the session");
      return;
    }
    let again = new NRFGainPoll();
    again.service = this;
    delay.DelayCallback(again, 0.5);
  }

  // Runs until AudioXL is available, then hands it every track. Bounded, so a missing or broken
  // AudioXL costs a minute of polling rather than a permanent timer. This is the ONLY step allowed
  // to wait: everything the engine reads at boot is written as its resource loads.
  public func Poll() -> Void {
    if this.m_audioDone { return; }

    if NRFAudio.Available() {
      this.RegisterAudio();
      return;
    }

    this.m_polls += 1;
    if this.m_polls > 120 {
      NRFLog("AudioXL never became available - no track has audio, so no station can sound");
      return;
    }

    // Before a session exists there is no DelaySystem. Session/Ready calls back in, so a failure
    // to schedule here is a wait rather than a dead end.
    let delay = GameInstance.GetDelaySystem(GetGameInstance());
    if !IsDefined(delay) {
      NRFLog(s"no DelaySystem yet - waiting for the session (poll \(this.m_polls))");
      return;
    }
    let again = new NRFPoll();
    again.service = this;
    delay.DelayCallback(again, 0.5);
  }

  // --- the audio event table ------------------------------------------------------------------------
  // An event present in the registry but absent from this table cannot be posted by name, and fails
  // silently. The duration here is what the station schedules the next track against, and **it must
  // be in the table while the table loads**: the engine reads it once, at boot. A row with a zero
  // duration makes the station pick a track at random instead of running on the clock.

  private cb func OnEventsMetadata(event: ref<ResourceEvent>) {
    this.RegisterEvents(event.GetResource() as JsonResource);
  }

  private cb func OnEventsReady(token: ref<ResourceToken>) {
    this.RegisterEvents(token.GetResource() as JsonResource);
  }

  private func RegisterEvents(resource: ref<JsonResource>) -> Void {
    if !IsDefined(resource) || this.m_eventsDone { return; }
    let events = resource.root as audioAudioEventArray;
    if !IsDefined(events) { return; }
    this.m_eventsDone = true;

    let added: Int32 = 0;
    let total: Float = 0.0;
    let station: Int32 = 0;
    let count: Int32 = NRF_StationCount();
    while station < count {
      let tracks: Int32 = NRF_StationTrackCount(station);
      let t: Int32 = 0;
      while t < tracks {
        let name: CName = NRF_StationTrack(station, t);
        let duration: Float = NRF_StationTrackDuration(station, t);
        if duration <= 0.0 {
          NRFLog(s"\(name) has no length - not added to the event table");
        } else {
          if !this.HasEvent(events, name) {
            let row: audioAudioEventMetadataArrayElement;
            row.redId = name;
            row.wwiseId = NRFAudio.WwiseId(name);
            row.isLooping = false;
            row.maxAttenuation = 0.0;
            row.minDuration = duration;
            row.maxDuration = duration;
            ArrayPush(events.events, row);
            added += 1;
            total += duration;
          }
        }
        t += 1;
      }
      station += 1;
    }
    NRFLog(s"registered \(added) event(s) in the audio event table as it loaded, \(Cast<Int32>(total)) s of audio");
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

  // **Membership and the station entry are written while this resource LOADS, and never later.** The
  // engine builds its station set once, from this resource. A station whose entry arrives even a few
  // seconds after is never constructed - the data is present and every receiver is silent.
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

    NRFLog(s"registered \(name) as the metadata loaded: \(ArraySize(station.tracks)) track(s), map now lists \(ArraySize(map.radioStations))");
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
    row.primaryLocKey = NRF_StationTrackKeyHash(station, track);
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
      added += this.AddText(screens, NRF_StationKey(station), NRF_StationKeyHash(station),
                            NRF_StationKeyHash64(station), NRF_StationDisplayName(station));
      let tracks: Int32 = NRF_StationTrackCount(station);
      let t: Int32 = 0;
      while t < tracks {
        added += this.AddText(screens, NRF_StationTrackKey(station, t),
                              NRF_StationTrackKeyHash(station, t),
                              NRF_StationTrackKeyHash64(station, t),
                              NRF_StationTrackTitle(station, t));
        t += 1;
      }
      station += 1;
    }
    NRFLog(s"registered \(added) string(s) in onscreens");
  }

  // **The localization list is SORTED by primaryKey and searched with a binary search.** A row
  // appended to the end is unreachable, whatever its key: the lookup fails and the widget keeps
  // the text it already had.
  //
  // A key is registered under BOTH hash widths, exactly as ArchiveXL does it: the 32-bit row keeps
  // the key text, the 64-bit row does not, so a lookup by either width finds one.
  private func AddText(screens: ref<localizationPersistenceOnScreenEntries>, key: CName,
                       hash32: Uint64, hash64: Uint64, text: String) -> Int32 {
    if !IsNameValid(key) || hash32 == 0ul || StrLen(text) == 0 { return 0; }
    let added: Int32 = 0;
    added += this.InsertText(screens, hash32, NameToString(key), text);
    added += this.InsertText(screens, hash64, "", text);
    return added;
  }

  private func InsertText(screens: ref<localizationPersistenceOnScreenEntries>, hash: Uint64,
                          secondary: String, text: String) -> Int32 {
    let at: Int32 = this.Place(screens, hash);
    if at < 0 { return 0; }

    let row = new localizationPersistenceOnScreenEntry();
    row.primaryKey = hash;
    row.secondaryKey = secondary;
    row.femaleVariant = text;
    row.maleVariant = text;
    ArrayInsert(screens.entries, at, row);
    return 1;
  }

  // The index the row belongs at, or -1 when that key is already present. Binary search, because
  // the list runs to tens of thousands of rows and this runs once per string.
  private func Place(screens: ref<localizationPersistenceOnScreenEntries>, hash: Uint64) -> Int32 {
    let low: Int32 = 0;
    let high: Int32 = ArraySize(screens.entries);
    while low < high {
      let mid: Int32 = (low + high) / 2;
      let at: Uint64 = screens.entries[mid].primaryKey;
      if at == hash {
        return -1;
      }
      if at < hash {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}
