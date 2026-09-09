// ======================================================================================
// Mod Name: Native Radio Framework
// Author: Spuddeh
// Description: Where each station is in its schedule, observed from the engine's own clock.
// File Version: 0.2.0
// ======================================================================================
//
// **The engine runs every station's schedule whether or not anything is tuned to it**, and
// `GetRadioStationCurrentTrackName` answers for a custom station exactly as it does for a vanilla
// one. So the framework never has to keep a schedule of its own: it watches the engine's answer and
// records the instant it changes.
//
// That instant is a slot boundary. The offset into the current track, at any later instant, is the
// time since it. **Before the first observed boundary the offset is unknown** - the station was
// already partway through a track when the watch began - and the answer is -1 rather than 0, so a
// caller can tell "not yet known" from "just started".
//
// **What that function returns is the track's LOCALIZATION KEY, not its event name.** The CName it
// hands back carries the key's hash and no text, so printing it yields nothing and reading it as a
// name is what makes a running schedule look like an idle one. A station's own keys are minted by
// the plugin and read back through `NRF_StationTrackKey`, so the key is matched against those to
// name the slot. A key matching none of them is the engine's "nothing playing" answer, whatever
// text that sentinel carries.
//
// Resolution is the poll interval, one second. A resume is placed to within that.

module NativeRadioFramework

// One station's place in its own schedule. `at` is sim time, which stops when the game does, and
// the radio's voices stop with it. `index` is the track's place in the station's own list.
public class NRFSlot {
  public let station: CName;
  public let stationIndex: Int32;
  public let track: CName;
  public let index: Int32;
  public let at: Float;
  public let seen: Bool;
}

public class NRFClockTick extends DelayCallback {
  public let clock: wref<NRFStationClock>;
  public let generation: Int32;

  public func Call() -> Void {
    if IsDefined(this.clock) {
      this.clock.Tick(this.generation);
    }
  }
}

// The watch. One instance, owned by the service, started whenever a session becomes ready and
// re-armed by each tick.
//
// **A session's delay callbacks do not survive that session, and Session/Ready fires more than
// once** - the main menu is a session, and loading a save is another. A watch that starts on the
// first and refuses to start again is dead from the moment the save loads: its chain was cleared
// with the session that owned it, and nothing re-enters. So every Session/Ready starts a new chain,
// and a GENERATION retires the old one rather than letting two run side by side.
public class NRFStationClock extends IScriptable {

  private let m_slots: array<ref<NRFSlot>>;
  private let m_generation: Int32;
  private let m_ticks: Int32;
  private let m_reports: Int32;

  public func Start() -> Void {
    let count: Int32 = NRF_StationCount();
    if count <= 0 { return; }

    if ArraySize(this.m_slots) == 0 {
      let i: Int32 = 0;
      while i < count {
        let name: CName = NRF_StationName(i);
        if IsNameValid(name) {
          let slot = new NRFSlot();
          slot.station = name;
          slot.stationIndex = i;
          ArrayPush(this.m_slots, slot);
        }
        i += 1;
      }
    }

    // A new session restarts every station's schedule and its clock, so nothing observed under the
    // old one can be counted from.
    let i: Int32 = 0;
    while i < ArraySize(this.m_slots) {
      this.m_slots[i].track = n"";
      this.m_slots[i].index = -1;
      this.m_slots[i].at = 0.0;
      this.m_slots[i].seen = false;
      i += 1;
    }
    this.m_ticks = 0;
    this.m_reports = 0;

    this.m_generation += 1;
    NRFLog(s"watching the schedule of \(ArraySize(this.m_slots)) station(s), generation \(this.m_generation)");
    this.Tick(this.m_generation);
  }

  // A slot takes its first track without calling it a boundary, because the station was already
  // partway through it. Only a change from one track to another is a boundary, and only then is an
  // offset knowable.
  public func Tick(generation: Int32) -> Void {
    if generation != this.m_generation { return; }
    let now: Float = this.Now();
    this.m_ticks += 1;
    this.Report(now);

    let i: Int32 = 0;
    while i < ArraySize(this.m_slots) {
      let slot = this.m_slots[i];
      let current: CName = GetRadioStationCurrentTrackName(slot.station);
      let index: Int32 = this.TrackOf(slot.stationIndex, current);
      if index >= 0 && index != slot.index {
        let had: Bool = slot.index >= 0;
        let leaving: Int32 = slot.index;
        let held: Float = now - slot.at;
        slot.track = current;
        slot.index = index;
        slot.at = now;
        if had {
          slot.seen = true;
          // **A slot the engine re-posts reports the same key, so a repeat is invisible as a
          // boundary and is only visible in how long the slot was held.** A track held for about
          // twice its declared length played twice; the declared length is what the station
          // schedules against, so the two numbers side by side say which is wrong.
          let declared: Float = NRF_StationTrackDuration(slot.stationIndex, leaving);
          NRFLog(s"\(slot.station) moved to track \(index) at \(now) - track \(leaving) held \(held) s, declared \(declared) s");
        } else {
          NRFLog(s"\(slot.station) is on track \(index), start time unknown");
        }
      }
      i += 1;
    }
    this.Arm(generation);
  }

  // The track this key names, or -1 for a key naming none of the station's tracks.
  //
  // **The CName the engine hands back carries a localization key's hash and no text, so it never
  // equals a CName built from the key's own string.** Comparing the two directly matches nothing
  // and reports a running station as idle. `GetLocalizedTextByKey` is what resolves a key of that
  // shape - it is how the dashboard turns the same value into a song title - so the title is what
  // identifies the track, against the titles the framework registered for it.
  private func TrackOf(station: Int32, key: CName) -> Int32 {
    if !IsNameValid(key) { return -1; }
    let title: String = GetLocalizedTextByKey(key);
    if StrLen(title) == 0 { return -1; }
    let tracks: Int32 = NRF_StationTrackCount(station);
    let t: Int32 = 0;
    while t < tracks {
      if StrCmp(title, NRF_StationTrackTitle(station, t)) == 0 { return t; }
      t += 1;
    }
    return -1;
  }

  // **A watch that logs only what it expects cannot tell silence from a stopped clock.** This says
  // which track each station resolves to, so a run that produces no boundary distinguishes "the
  // engine names no track" from "the tick chain died". Every tick for the first five, then once a
  // minute, and bounded.
  private func Report(now: Float) -> Void {
    if this.m_reports >= 25 { return; }
    if this.m_ticks > 5 && this.m_ticks % 60 != 0 { return; }
    this.m_reports += 1;

    let line: String = s"tick \(this.m_ticks) at \(now):";
    let i: Int32 = 0;
    while i < ArraySize(this.m_slots) {
      let slot = this.m_slots[i];
      let current: CName = GetRadioStationCurrentTrackName(slot.station);
      // The resolved title as well as the index: a key that resolves to a title matching no track
      // is a different fault from one that resolves to nothing, and the index alone hides which.
      line += s" \(slot.station)=track \(this.TrackOf(slot.stationIndex, current)) \"\(GetLocalizedTextByKey(current))\"";
      i += 1;
    }
    // Growl FM is the control. Its key belongs to no custom station, so only the title it resolves
    // to is worth reading, and a vanilla song title there proves the lookup itself works.
    let control: CName = GetRadioStationCurrentTrackName(n"radio_station_12_growl_fm");
    line += s" | control growl_fm=\"\(GetLocalizedTextByKey(control))\"";
    NRFLog(line);
  }

  // The key the engine says a station is playing.
  public func CurrentTrack(station: CName) -> CName {
    let slot = this.Find(station);
    if !IsDefined(slot) { return n""; }
    return slot.track;
  }

  // The track the engine says a station is playing, as its place in the station's own list, or -1
  // before the station has started one.
  public func CurrentIndex(station: CName) -> Int32 {
    let slot = this.Find(station);
    if !IsDefined(slot) { return -1; }
    return slot.index;
  }

  // Seconds into the current track, or -1 when no boundary has been observed for this station yet.
  // **-1 is not 0.** A caller with no boundary to count from has nothing to resume to, and starting
  // that track from 0 is a fallback rather than a measurement, so the two cases stay apart here.
  public func Offset(station: CName) -> Float {
    let slot = this.Find(station);
    if !IsDefined(slot) || !slot.seen { return -1.0; }
    let elapsed: Float = this.Now() - slot.at;
    if elapsed < 0.0 { return 0.0; }
    return elapsed;
  }

  private func Find(station: CName) -> ref<NRFSlot> {
    let i: Int32 = 0;
    while i < ArraySize(this.m_slots) {
      if Equals(this.m_slots[i].station, station) { return this.m_slots[i]; }
      i += 1;
    }
    return null;
  }

  private func Now() -> Float {
    return EngineTime.ToFloat(GameInstance.GetSimTime(GetGameInstance()));
  }

  private func Arm(generation: Int32) -> Void {
    let delay = GameInstance.GetDelaySystem(GetGameInstance());
    if !IsDefined(delay) { return; }
    let tick = new NRFClockTick();
    tick.clock = this;
    tick.generation = generation;
    delay.DelayCallback(tick, 1.0);
  }
}
