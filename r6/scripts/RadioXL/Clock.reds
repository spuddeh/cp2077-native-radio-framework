// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Where each station is in its schedule, and where a tuned-away track resumes from.
// File Version: 0.3.0
// Credits: AudioXL by DigitalVixen.
// ======================================================================================
//
// **The engine runs a station's schedule only while a receiver plays it, and it never hands the
// renderer an offset.** So a custom station tuned away from and back again would restart its track
// from 0:00. This watch is what resumes it instead:
//
//   - Every second, for each station, the engine is asked which track it is on
//     (`GetRadioStationCurrentTrackName`). A change is a slot boundary.
//   - While a station's current track has a voice playing, that voice's position is read from
//     AudioXL and written back to the row as the point the NEXT voice on it starts from
//     (`PlayFrom`). A tune-away retires the voice; a tune-back posts the row again and it starts
//     where it left off, within one tick.
//   - At a slot boundary the row that ended has its pending start cleared, so a track that played
//     through starts from 0:00 the next time the schedule reaches it.
//   - A new session clears every pending start, because the engine's schedule restarts with it.
//
// Before the first observed play the offset is unknown and the voice starts at 0, which is the
// engine's own behaviour on this path.
//
// **What `GetRadioStationCurrentTrackName` returns is the track's LOCALIZATION KEY, not its event
// name.** The CName carries the key's hash and no text, so it never equals a CName built from the
// key's string; `GetLocalizedTextByKey` resolves it to the title, which is matched against the
// titles the framework registered.
//
// Resolution is the poll interval, one second. A resume lands within that of where it left off.

module RadioXL

// One station's place in its own schedule. `at` is sim time, which stops when the game does, and
// the radio's voices stop with it. `index` is the track's place in the station's own list.
public class RadioXLSlot {
  public let station: CName;
  public let stationIndex: Int32;
  public let track: CName;
  public let index: Int32;
  public let at: Float;
  public let seen: Bool;
  // The event row of the current track, whether a voice on it was heard playing on the last tick,
  // its last read position, and whether that position is pending on the row as a start offset.
  public let row: CName;
  public let playing: Bool;
  public let position: Float;
  public let pending: Bool;
}

public class RadioXLClockTick extends DelayCallback {
  public let clock: wref<RadioXLStationClock>;
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
// once** - the main menu is a session, and loading a save is another. So every Session/Ready starts
// a new chain, and a GENERATION retires the old one rather than letting two run side by side.
public class RadioXLStationClock extends IScriptable {

  private let m_slots: array<ref<RadioXLSlot>>;
  private let m_generation: Int32;
  private let m_ticks: Int32;
  private let m_reports: Int32;

  public func Start() -> Void {
    let count: Int32 = RadioXL_StationCount();
    if count <= 0 { return; }

    if ArraySize(this.m_slots) == 0 {
      let i: Int32 = 0;
      while i < count {
        let name: CName = RadioXL_StationName(i);
        if IsNameValid(name) {
          let slot = new RadioXLSlot();
          slot.station = name;
          slot.stationIndex = i;
          ArrayPush(this.m_slots, slot);
        }
        i += 1;
      }
    }

    // A new session restarts every station's schedule and its clock, so nothing observed under the
    // old one can be counted from, and a start offset left pending on a row would land on a track
    // the new schedule begins from 0.
    let i: Int32 = 0;
    while i < ArraySize(this.m_slots) {
      let slot = this.m_slots[i];
      this.ClearPending(slot);
      slot.track = n"";
      slot.index = -1;
      slot.at = 0.0;
      slot.seen = false;
      slot.row = n"";
      slot.playing = false;
      slot.position = 0.0;
      i += 1;
    }
    this.m_ticks = 0;
    this.m_reports = 0;

    this.m_generation += 1;
    RadioXLLog(s"watching the schedule of \(ArraySize(this.m_slots)) station(s), generation \(this.m_generation)");
    this.Tick(this.m_generation);
  }

  // A slot takes its first track without calling it a boundary, because the station was already
  // partway through it. Only a change from one track to another is a boundary.
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
        // The track that ended starts from 0:00 next time; only a tune-away keeps a position.
        this.ClearPending(slot);
        slot.track = current;
        slot.index = index;
        slot.at = now;
        slot.row = RadioXL_StationTrack(slot.stationIndex, index);
        slot.playing = false;
        slot.position = 0.0;
        if had {
          slot.seen = true;
          // **A slot the engine re-posts reports the same key, so a repeat is invisible as a
          // boundary and is only visible in how long the slot was held.** A track held for about
          // twice its declared length played twice; the declared length is what the station
          // schedules against, so the two numbers side by side say which is wrong.
          let declared: Float = RadioXL_StationTrackDuration(slot.stationIndex, leaving);
          RadioXLLog(s"\(slot.station) moved to track \(index) at \(now) - track \(leaving) held \(held) s, declared \(declared) s");
        } else {
          RadioXLLog(s"\(slot.station) is on track \(index), start time unknown");
        }
      }
      this.Follow(slot);
      i += 1;
    }
    this.Arm(generation);
  }

  // The resume itself. **A receiver that tunes away does not stop the voice**: it keeps playing,
  // unheard, and the station carries on, so the point to resume from is wherever that voice is now.
  // A tune-back posts the row again, and the position read here is written back each tick as the
  // start of that next voice. The offset is consumed by one voice, so it is written every tick.
  private func Follow(slot: ref<RadioXLSlot>) -> Void {
    if !IsNameValid(slot.row) { return; }
    let playing: Bool = RadioXLAudio.IsPlaying(slot.row);
    if playing {
      let position: Float = RadioXLAudio.Position(slot.row);
      // A position behind the last one is a fresh voice on the row. What it started from, against
      // what was pending, says whether AudioXL applied the offset to a voice the engine posted.
      if position > 0.0 && position + 0.5 < slot.position {
        let verdict: String = slot.pending ? "pending was accepted by PlayFrom" : "PlayFrom had refused the pending start";
        RadioXLLog(s"\(slot.station) track \(slot.index) restarted at \(position) s, pending start was \(slot.position) s - \(verdict)");
      }
      // Live with no position is a voice AudioXL counts but does not report on. Seen after a
      // second re-post of the same row; logged so the window is visible, once per stretch.
      if position <= 0.0 && slot.position > 0.0 {
        RadioXLLog(s"\(slot.station) track \(slot.index): live, position reads 0 (was \(slot.position) s)");
        slot.position = 0.0;
      }
      if position > 0.0 {
        slot.position = position;
        let accepted: Bool = RadioXLAudio.PlayFrom(slot.row, position);
        if !accepted && slot.pending {
          RadioXLLog(s"\(slot.station) track \(slot.index): PlayFrom refused \(position) s");
        }
        slot.pending = accepted;
      }
      if !slot.playing {
        RadioXLLog(s"\(slot.station) track \(slot.index) playing from \(slot.position) s");
      }
    } else {
      if slot.playing {
        RadioXLLog(s"\(slot.station) track \(slot.index) stopped at \(slot.position) s - the next voice on it resumes there");
      }
    }
    slot.playing = playing;
  }

  private func ClearPending(slot: ref<RadioXLSlot>) -> Void {
    if slot.pending && IsNameValid(slot.row) {
      RadioXLAudio.PlayFrom(slot.row, 0.0);
    }
    slot.pending = false;
  }

  // The track this key names, or -1 for a key naming none of the station's tracks.
  private func TrackOf(station: Int32, key: CName) -> Int32 {
    if !IsNameValid(key) { return -1; }
    let title: String = GetLocalizedTextByKey(key);
    if StrLen(title) == 0 { return -1; }
    let tracks: Int32 = RadioXL_StationTrackCount(station);
    let t: Int32 = 0;
    while t < tracks {
      if StrCmp(title, RadioXL_StationTrackTitle(station, t)) == 0 { return t; }
      t += 1;
    }
    return -1;
  }

  // **A watch that logs only what it expects cannot tell silence from a stopped clock.** This says
  // which track each station resolves to, so a run that produces no boundary distinguishes "the
  // engine names no track" from "the tick chain died". Every tick for the first five, then once a
  // minute, and bounded.
  private func Report(now: Float) -> Void {
    if this.m_reports >= 60 { return; }
    if this.m_ticks > 5 && this.m_ticks % 15 != 0 { return; }
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
    // Two vanilla controls. Their keys belong to no custom station, so only the title each resolves
    // to is worth reading: a vanilla song title proves the lookup works, and a title that changes
    // while the station is not being listened to proves a tuned-then-left vanilla station advances.
    let control: CName = GetRadioStationCurrentTrackName(n"radio_station_12_growl_fm");
    line += s" | control growl_fm=\"\(GetLocalizedTextByKey(control))\"";
    let pop: CName = GetRadioStationCurrentTrackName(n"radio_station_05_pop");
    line += s" body_heat=\"\(GetLocalizedTextByKey(pop))\"";
    RadioXLLog(line);
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

  // Seconds into the current track as last heard, or -1 when no voice on it has been heard yet.
  // **-1 is not 0.** A caller with nothing heard has nothing to resume to.
  public func Offset(station: CName) -> Float {
    let slot = this.Find(station);
    if !IsDefined(slot) || !slot.pending { return -1.0; }
    return slot.position;
  }

  private func Find(station: CName) -> ref<RadioXLSlot> {
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
    let tick = new RadioXLClockTick();
    tick.clock = this;
    tick.generation = generation;
    delay.DelayCallback(tick, 1.0);
  }
}
