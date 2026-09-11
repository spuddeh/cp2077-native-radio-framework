// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Builds each declared station out of the engine's own radio systems.
// File Version: 0.3.0
// Credits: RED4ext by WopsS. AudioXL by DigitalVixen.
// ======================================================================================

module RadioXL

@if(ModuleExists("RedLogger"))
import RedLogger.*

@if(ModuleExists("RedLogger"))
public func RadioXLLog(msg: String) -> Void {
  RedLog.Append("RadioXL", msg);
}

@if(!ModuleExists("RedLogger"))
public func RadioXLLog(msg: String) -> Void {}

// **A declared duration must sit BELOW the decoded length, and an exact one does not.** The engine
// posts a slot's track again when the voice ends while that slot is still current, so a duration at
// or above the real length loses that race about half the time: the row holds a 32-bit float whose
// step is 15 microseconds at three minutes, and the rounding decides the sign. Measured on two
// tracks four microseconds either side of their own length - the one rounded up played twice, the
// one rounded down played once.
//
// A station that under-declares does not run the race at all: the slot ends first and the engine
// waits for the voice, so the margin costs no audio. Vanilla is built that way, and by far more -
// `mus_radio_12_afterlife` declares 166 s for 169.7 s.
//
// **What caps the margin is that the station clock free-runs.** A slot shorter than its track
// advances the clock a little further than one slot per post, and the excess accumulates until a
// slot is passed over and its track goes unplayed. Half a second is 33,000 times the float step and
// reaches that point about once in 450 tracks.
public func RadioXLScheduleMargin() -> Float {
  return 0.5;
}

// **A station's level belongs on its send, not in its samples**, so a track registered against this
// framework's own type is handed to AudioXL untouched. The game's `mod_sfx_radio` object has no send
// this framework can set, and its own reaches a world device 3 to 7 dB hotter than any vanilla
// station, so a full-scale sample wraps there. This is the trim that path needs, measured: -5 dB
// lands both of its sends inside the vanilla range.
//
// It MULTIPLIES a station's own gain rather than replacing it, so a manifest that asks for a level
// gets the same relative result whichever type carries the sound.
public func RadioXLFallbackTrim() -> Float {
  return 0.56;
}

// Supplied by the plugin, which reads the station manifests. The list is declared once, in the
// manifest, and read from here - never restated in script.
public native func RadioXL_StationCount() -> Int32;
public native func RadioXL_DialPosition(index: Int32) -> Int32;
public native func RadioXL_DialStation(index: Int32) -> Int32;
public native func RadioXL_StationName(index: Int32) -> CName;
public native func RadioXL_StationKey(index: Int32) -> CName;
public native func RadioXL_StationDisplayName(index: Int32) -> String;
public native func RadioXL_StationIcon(index: Int32) -> String;
public native func RadioXL_StationAtlas(index: Int32) -> String;
public native func RadioXL_StationSpeaker(index: Int32) -> String;
public native func RadioXL_StationGain(index: Int32) -> Float;
public native func RadioXL_StationTrackCount(index: Int32) -> Int32;
public native func RadioXL_StationTrack(index: Int32, track: Int32) -> CName;
public native func RadioXL_StationTrackKey(index: Int32, track: Int32) -> CName;
public native func RadioXL_StationTrackFile(index: Int32, track: Int32) -> String;
public native func RadioXL_StationTrackTitle(index: Int32, track: Int32) -> String;
public native func RadioXL_StationTrackDuration(index: Int32, track: Int32) -> Float;
public native func RadioXL_StationKeyHash(index: Int32) -> Uint64;
public native func RadioXL_StationTrackKeyHash(index: Int32, track: Int32) -> Uint64;
public native func RadioXL_StationKeyHash64(index: Int32) -> Uint64;
public native func RadioXL_StationTrackKeyHash64(index: Int32, track: Int32) -> Uint64;

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
public func RadioXLSpeaker(name: String) -> audioRadioSpeakerType {
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
public class RadioXLPoll extends DelayCallback {
  public let service: wref<RadioXLService>;

  public func Call() -> Void {
    if IsDefined(this.service) {
      this.service.Poll();
    }
  }
}

// A row AudioXL queued gets its level trim on a later pass. This carries that retry.
public class RadioXLGainPoll extends DelayCallback {
  public let service: wref<RadioXLService>;

  public func Call() -> Void {
    if IsDefined(this.service) {
      this.service.ApplyGains();
    }
  }
}

public class RadioXLService extends ScriptableService {

  private let m_tokens: array<ref<ResourceToken>>;
  private let m_audioDone: Bool;
  private let m_cookedDone: Bool;
  private let m_eventsDone: Bool;
  private let m_textDone: Bool;
  private let m_polls: Int32;
  private let m_gainPending: Bool;
  private let m_gainPolls: Int32;
  private let m_ownType: Bool;

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

  // The framework's own bank, and the type it defines. **The type decides where a station's sound
  // is sent**: `radioxl_radio` carries a vanilla station's send trims, while the game's `mod_sfx_radio`
  // is trimmed 3 to 7 dB above every station on the dial. The fallback is not a degraded mode - it
  // is what every station sounded like before the bank existed - so a bank that fails to load costs
  // level accuracy and nothing else.
  // **The load result is reported, not interpreted.** A boolean says which branch was taken and
  // nothing about why, and the codes differ: 1 is a load, 69 a bank already loaded, and the rest are
  // distinct failures worth telling apart.
  private func AudioType() -> CName {
    let path: String = "red4ext/plugins/RadioXL/radioxl_routing.bnk";
    let result: Int32 = RadioXLAudio.LoadBankResult(path);
    this.m_ownType = result == 1 || result == 69;
    let chosen: String = this.m_ownType ? "radioxl_radio" : "mod_sfx_radio (the game's)";
    RadioXLLog(s"routing bank load returned \(result), type is \(chosen)");
    if this.m_ownType {
      return n"radioxl_radio";
    }
    return n"mod_sfx_radio";
  }

  // What a track's samples are scaled by. 1.0 on this framework's own type, because the send carries
  // the level there; the fallback's trim on the game's type, which has no send to set.
  private func Gain(station: Int32) -> Float {
    let gain: Float = RadioXL_StationGain(station);
    if this.m_ownType { return gain; }
    return gain * RadioXLFallbackTrim();
  }

  private func RegisterAudio() -> Void {
    if this.m_audioDone { return; }
    this.m_audioDone = true;

    let type: CName = this.AudioType();
    let registered: Int32 = 0;
    let station: Int32 = 0;
    let count: Int32 = RadioXL_StationCount();
    while station < count {
      let tracks: Int32 = RadioXL_StationTrackCount(station);
      let gain: Float = this.Gain(station);
      let t: Int32 = 0;
      while t < tracks {
        let event: CName = RadioXL_StationTrack(station, t);
        let file: String = RadioXL_StationTrackFile(station, t);
        if IsNameValid(event) && StrLen(file) > 0 && !RadioXLAudio.Has(event) {
          if RadioXLAudio.Register(event, file, type) {
            registered += 1;
            if !RadioXLAudio.SetGain(event, gain) {
              this.m_gainPending = true;
            }
          } else {
            RadioXLLog(s"AudioXL refused \(event) - \(file)");
          }
        }
        t += 1;
      }
      station += 1;
    }
    RadioXLLog(s"registered \(registered) track(s) with AudioXL");
    // **A registration returning true says the row exists, not that anything can play it.** If the
    // type's event is absent the engine posts into nothing, which sounds exactly like a broken file.
    let probe: CName = RadioXL_StationTrack(0, 0);
    RadioXLLog(s"probe \(probe): row \(RadioXLAudio.Has(probe)), wwiseId \(RadioXLAudio.WwiseId(probe)), decoded \(RadioXLAudio.Duration(probe)) s");
    if this.m_gainPending {
      this.ApplyGains();
    }
  }

  // A row AudioXL queued has no gain to set at registration time. Walk every track again until each
  // SetGain lands, bounded, so a row that never appears costs a few seconds rather than a timer.
  public func ApplyGains() -> Void {
    let failed: Int32 = 0;
    let station: Int32 = 0;
    let count: Int32 = RadioXL_StationCount();
    while station < count {
      let tracks: Int32 = RadioXL_StationTrackCount(station);
      let gain: Float = this.Gain(station);
      let t: Int32 = 0;
      while t < tracks {
        let event: CName = RadioXL_StationTrack(station, t);
        if IsNameValid(event) && !RadioXLAudio.SetGain(event, gain) {
          failed += 1;
        }
        t += 1;
      }
      station += 1;
    }
    if failed == 0 {
      this.m_gainPending = false;
      RadioXLLog("level trim applied to every track");
      return;
    }
    this.m_gainPolls += 1;
    if this.m_gainPolls > 20 {
      RadioXLLog(s"\(failed) track(s) never got a row in AudioXL, so their level trim was not applied");
      this.m_gainPending = false;
      return;
    }
    // AudioXL's Available() is the plugin, not the engine's audio system, so the first pass runs
    // before any row exists and before a session has a DelaySystem. Session/Ready calls back in.
    let delay = GameInstance.GetDelaySystem(GetGameInstance());
    if !IsDefined(delay) {
      RadioXLLog(s"\(failed) track(s) have no row yet - level trim deferred to the session");
      return;
    }
    let again = new RadioXLGainPoll();
    again.service = this;
    delay.DelayCallback(again, 0.5);
  }

  // Runs until AudioXL is available, then hands it every track. Bounded, so a missing or broken
  // AudioXL costs a minute of polling rather than a permanent timer. This is the ONLY step allowed
  // to wait: everything the engine reads at boot is written as its resource loads.
  public func Poll() -> Void {
    if this.m_audioDone { return; }

    if RadioXLAudio.Available() {
      this.RegisterAudio();
      return;
    }

    this.m_polls += 1;
    if this.m_polls > 120 {
      RadioXLLog("AudioXL never became available - no track has audio, so no station can sound");
      return;
    }

    // Before a session exists there is no DelaySystem. Session/Ready calls back in, so a failure
    // to schedule here is a wait rather than a dead end.
    let delay = GameInstance.GetDelaySystem(GetGameInstance());
    if !IsDefined(delay) {
      RadioXLLog(s"no DelaySystem yet - waiting for the session (poll \(this.m_polls))");
      return;
    }
    let again = new RadioXLPoll();
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

    // **The custom-sound TYPE is posted by name, so it needs a row here exactly as a track does.**
    // AudioXL stores a row's type as the CName hash of the type string, and the engine resolves
    // that name through this table to reach the Wwise event. A type absent from it plays nothing
    // and reports nothing - the registration succeeds, the bank loads, and every station is silent.
    // AudioXL registers its own six `axl_*` types here for the same reason.
    let typeRow: audioAudioEventMetadataArrayElement;
    typeRow.redId = n"radioxl_radio";
    typeRow.wwiseId = RadioXLAudio.WwiseId(n"radioxl_radio");
    typeRow.isLooping = false;
    typeRow.maxAttenuation = 0.0;
    typeRow.minDuration = 0.0;
    typeRow.maxDuration = 0.0;
    if typeRow.wwiseId == 0u {
      RadioXLLog("the radioxl_radio type has no Wwise id - the routing bank cannot be posted, so every station falls to the game's type");
    } else {
      if !this.HasEvent(events, n"radioxl_radio") {
        ArrayPush(events.events, typeRow);
        RadioXLLog(s"registered the radioxl_radio type in the audio event table, wwiseId \(typeRow.wwiseId)");
      }
    }

    let added: Int32 = 0;
    let total: Float = 0.0;
    let station: Int32 = 0;
    let count: Int32 = RadioXL_StationCount();
    while station < count {
      let tracks: Int32 = RadioXL_StationTrackCount(station);
      let t: Int32 = 0;
      while t < tracks {
        let name: CName = RadioXL_StationTrack(station, t);
        let duration: Float = RadioXL_StationTrackDuration(station, t);
        if duration <= 0.0 {
          RadioXLLog(s"\(name) has no length - not added to the event table");
        } else {
          if !this.HasEvent(events, name) {
            let row: audioAudioEventMetadataArrayElement;
            row.redId = name;
            row.wwiseId = RadioXLAudio.WwiseId(name);
            row.isLooping = false;
            row.maxAttenuation = 0.0;
            row.minDuration = duration - RadioXLScheduleMargin();
            row.maxDuration = duration - RadioXLScheduleMargin();
            ArrayPush(events.events, row);
            added += 1;
            total += duration;
          }
        }
        t += 1;
      }
      station += 1;
    }
    RadioXLLog(s"registered \(added) event(s) in the audio event table as it loaded, \(Cast<Int32>(total)) s of audio");
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

    let count: Int32 = RadioXL_StationCount();
    if count <= 0 {
      RadioXLLog("no stations registered - either none are installed, or the roster was not patched");
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
      RadioXLLog("no station map in this metadata resource - nothing registered");
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
    let name: CName = RadioXL_StationName(index);
    if !IsNameValid(name) { return; }

    if IsDefined(this.Find(cooked, name)) {
      RadioXLLog(s"\(name) is already defined - left alone");
      return;
    }

    let station = new audioRadioStationMetadata();
    station.name = name;
    // The DJ, and `None` is the default - a station with no speaker plays. Vanilla names one on
    // every station, so a station mod that wants one asks for it by name in its manifest.
    station.speaker = RadioXLSpeaker(RadioXL_StationSpeaker(index));

    let tracks: Int32 = RadioXL_StationTrackCount(index);
    let t: Int32 = 0;
    while t < tracks {
      let event: CName = RadioXL_StationTrack(index, t);
      if IsNameValid(event) {
        ArrayPush(station.tracks, event);
        this.AddTitle(titles, index, t, event);
      }
      t += 1;
    }

    if ArraySize(station.tracks) == 0 {
      RadioXLLog(s"\(name) lists no tracks - not registered");
      return;
    }

    ArrayPush(cooked.entries, station);
    if !ArrayContains(map.radioStations, name) {
      ArrayPush(map.radioStations, name);
    }

    RadioXLLog(s"registered \(name) as the metadata loaded: \(ArraySize(station.tracks)) track(s), map now lists \(ArraySize(map.radioStations))");
  }

  // The row the dashboard and the radio wheel read the song title from. `localizationKey` is a key,
  // and RegisterText is what makes it resolve.
  private func AddTitle(titles: ref<audioRadioTracksMetadata>, station: Int32, track: Int32,
                        event: CName) -> Void {
    if !IsDefined(titles) || StrLen(RadioXL_StationTrackTitle(station, track)) == 0 { return; }
    let i: Int32 = 0;
    while i < ArraySize(titles.radioTracks) {
      if Equals(titles.radioTracks[i].trackEventName, event) { return; }
      i += 1;
    }
    let row: audioRadioTrack;
    row.trackEventName = event;
    row.localizationKey = RadioXL_StationTrackKey(station, track);
    row.primaryLocKey = RadioXL_StationTrackKeyHash(station, track);
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
    let count: Int32 = RadioXL_StationCount();
    while station < count {
      added += this.AddText(screens, RadioXL_StationKey(station), RadioXL_StationKeyHash(station),
                            RadioXL_StationKeyHash64(station), RadioXL_StationDisplayName(station));
      let tracks: Int32 = RadioXL_StationTrackCount(station);
      let t: Int32 = 0;
      while t < tracks {
        added += this.AddText(screens, RadioXL_StationTrackKey(station, t),
                              RadioXL_StationTrackKeyHash(station, t),
                              RadioXL_StationTrackKeyHash64(station, t),
                              RadioXL_StationTrackTitle(station, t));
        t += 1;
      }
      station += 1;
    }
    RadioXLLog(s"registered \(added) string(s) in onscreens");
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
