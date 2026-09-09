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
// Resolution is the poll interval, one second. A resume is placed to within that.

module NativeRadioFramework

// One station's place in its own schedule. `at` is sim time, which stops when the game does, and
// the radio's voices stop with it.
public class NRFSlot {
  public let station: CName;
  public let track: CName;
  public let at: Float;
  public let seen: Bool;
}

public class NRFClockTick extends DelayCallback {
  public let clock: wref<NRFStationClock>;

  public func Call() -> Void {
    if IsDefined(this.clock) {
      this.clock.Tick();
    }
  }
}

// The watch. One instance, owned by the service, started when a session is ready and re-armed by
// each tick. A tick with no DelaySystem stops re-arming; the next Session/Ready starts it again.
public class NRFStationClock extends IScriptable {

  private let m_slots: array<ref<NRFSlot>>;
  private let m_running: Bool;
  private let m_ticks: Int32;
  private let m_reports: Int32;

  public func Start() -> Void {
    if this.m_running { return; }
    let count: Int32 = NRF_StationCount();
    if count <= 0 { return; }

    if ArraySize(this.m_slots) == 0 {
      let i: Int32 = 0;
      while i < count {
        let name: CName = NRF_StationName(i);
        if IsNameValid(name) {
          let slot = new NRFSlot();
          slot.station = name;
          slot.track = n"";
          slot.at = 0.0;
          slot.seen = false;
          ArrayPush(this.m_slots, slot);
        }
        i += 1;
      }
    }

    this.m_running = true;
    NRFLog(s"watching the schedule of \(ArraySize(this.m_slots)) station(s)");
    this.Tick();
  }

  // The engine's answer for a station that has not started playing is an invalid name, so a slot
  // takes its first track without calling it a boundary. Only a change from one valid name to
  // another is a boundary, and only then is an offset knowable.
  public func Tick() -> Void {
    let now: Float = this.Now();
    this.m_ticks += 1;
    this.Report(now);
    let i: Int32 = 0;
    while i < ArraySize(this.m_slots) {
      let slot = this.m_slots[i];
      let current: CName = GetRadioStationCurrentTrackName(slot.station);
      if IsNameValid(current) && !Equals(current, slot.track) {
        let had: Bool = IsNameValid(slot.track);
        slot.track = current;
        slot.at = now;
        if had {
          slot.seen = true;
          NRFLog(s"\(slot.station) moved to \(current) at \(now)");
        }
      }
      i += 1;
    }
    this.Arm();
  }

  // **A watch that logs only what it expects cannot tell silence from a stopped clock.** This says
  // what the native actually answered, for each watched station and for a vanilla control, so a run
  // that produces no boundary distinguishes "the engine names no track for a custom station" from
  // "the tick chain died". Every tick for the first five, then once a minute, and bounded.
  private func Report(now: Float) -> Void {
    if this.m_reports >= 25 { return; }
    if this.m_ticks > 5 && this.m_ticks % 60 != 0 { return; }
    this.m_reports += 1;

    let line: String = s"tick \(this.m_ticks) at \(now):";
    let i: Int32 = 0;
    while i < ArraySize(this.m_slots) {
      let station: CName = this.m_slots[i].station;
      line += s" \(station)=\(GetRadioStationCurrentTrackName(station))";
      i += 1;
    }
    // Growl FM is the control. An answer here with none beside it means the native works and a
    // custom station is absent from whatever it reads.
    let control: CName = GetRadioStationCurrentTrackName(n"radio_station_12_growl_fm");
    line += s" | control growl_fm=\(control)";
    NRFLog(line);
  }

  // The track the engine says a station is playing, valid only once it has started one.
  public func CurrentTrack(station: CName) -> CName {
    let slot = this.Find(station);
    if !IsDefined(slot) { return n""; }
    return slot.track;
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

  private func Arm() -> Void {
    let delay = GameInstance.GetDelaySystem(GetGameInstance());
    if !IsDefined(delay) {
      this.m_running = false;
      return;
    }
    let tick = new NRFClockTick();
    tick.clock = this;
    delay.DelayCallback(tick, 1.0);
  }
}
