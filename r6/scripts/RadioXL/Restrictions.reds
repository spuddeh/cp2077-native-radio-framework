// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Keeps the Radioport playing through a situation the player chose not to mute in.
// File Version: 0.3.0
// ======================================================================================
//
// The game silences the pocket radio through `PocketRadio.HandleRestriction`: each restriction is
// recorded, and while any is set the radio is turned off and every tune request is ignored. A
// custom station is a real station, so it is silenced the same way. **A switch that is off lifts
// that one restriction for every station on the Radioport**, the game's own included: the world's
// own value is recorded, and the pocket radio is handed the switched one.

module RadioXL

public class RadioXLRestrictions extends ScriptableSystem {

  // The value the game last reported for each restriction, before any switch was applied.
  private let m_actual: array<Bool>;

  public static func Get() -> ref<RadioXLRestrictions> {
    return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
      .Get(n"RadioXL.RadioXLRestrictions") as RadioXLRestrictions;
  }

  private func OnAttach() -> Void {
    let i: Int32 = 0;
    while i < EnumInt(PocketRadioRestrictions.PocketRadioRestrictionCount) {
      ArrayPush(this.m_actual, false);
      i += 1;
    }
  }

  public func Record(restriction: Int32, restricted: Bool) -> Void {
    if restriction >= 0 && restriction < ArraySize(this.m_actual) {
      this.m_actual[restriction] = restricted;
    }
  }

  public func Actual(restriction: Int32) -> Bool {
    return restriction >= 0 && restriction < ArraySize(this.m_actual) && this.m_actual[restriction];
  }

  // The value the pocket radio is told, for the station it has selected.
  // **A switch is a situation, and a situation can raise more than one restriction.** A holo call
  // raises the quest lock and the fast-travel block a millisecond before the call itself
  // (measured), so lifting the call alone leaves the radio silenced by its companions. While the
  // call is up and its switch is off, its companions are lifted with it; a companion raised on its
  // own, by a quest, still mutes as its own switch says.
  public static func IsCompanionOfLiftedCall(restriction: Int32) -> Bool {
    if restriction != EnumInt(PocketRadioRestrictions.BlockFastTravel) &&
       restriction != EnumInt(PocketRadioRestrictions.QuestContentLock) { return false; }
    let cfg = RadioXLConfig.Get();
    let state = RadioXLRestrictions.Get();
    return IsDefined(cfg) && IsDefined(state) &&
           state.Actual(EnumInt(PocketRadioRestrictions.PhoneCall)) &&
           !cfg.MutesOn(EnumInt(PocketRadioRestrictions.PhoneCall));
  }

  public static func Applied(restriction: Int32, restricted: Bool, station: Int32) -> Bool {
    if !restricted { return restricted; }
    let cfg = RadioXLConfig.Get();
    if !IsDefined(cfg) { return true; }
    if !cfg.MutesOn(restriction) { return false; }
    return !RadioXLRestrictions.IsCompanionOfLiftedCall(restriction);
  }

  // Feed every restriction back through the pocket radio with its real value, so the wrap below
  // applies the switches as they stand now. Called when a switch changes.
  public static func Refresh() -> Void {
    let gi: GameInstance = GetGameInstance();
    if !GameInstance.IsValid(gi) { return; }
    let player = GetPlayer(gi);
    if !IsDefined(player) { return; }
    let radio = player.GetPocketRadio();
    let state = RadioXLRestrictions.Get();
    if !IsDefined(radio) || !IsDefined(state) { return; }
    let i: Int32 = 0;
    while i < EnumInt(PocketRadioRestrictions.PocketRadioRestrictionCount) {
      radio.HandleRestriction(IntEnum<PocketRadioRestrictions>(i), state.Actual(i));
      i += 1;
    }
  }
}

@wrapMethod(PocketRadio)
public final func HandleRestriction(restriction: PocketRadioRestrictions, restricted: Bool) -> Void {
  let state = RadioXLRestrictions.Get();
  if IsDefined(state) {
    state.Record(EnumInt(restriction), restricted);
  }
  let applied: Bool = RadioXLRestrictions.Applied(EnumInt(restriction), restricted, this.m_selectedStation);
  RadioXLLog(s"restriction \(EnumInt(restriction)) actual=\(restricted) applied=\(applied) station=\(this.m_selectedStation) overwritten=\(this.m_isRestrictionOverwritten)");
  wrappedMethod(restriction, applied);
  // The call's companions arrive before the call does, so they were applied on their own switch.
  // Now that the call is known, hand them their situation-aware value. The re-entry records the
  // same actual and cannot loop, because a companion is never the call.
  if Equals(restriction, PocketRadioRestrictions.PhoneCall) && IsDefined(state) {
    let companions: array<PocketRadioRestrictions> = [PocketRadioRestrictions.BlockFastTravel, PocketRadioRestrictions.QuestContentLock];
    let i: Int32 = 0;
    while i < ArraySize(companions) {
      let c: Int32 = EnumInt(companions[i]);
      if state.Actual(c) && !Equals(this.m_restrictions[c], RadioXLRestrictions.Applied(c, true, this.m_selectedStation)) {
        this.HandleRestriction(companions[i], true);
      }
      i += 1;
    }
  }
}

// Every turn-off of the pocket radio, with who asked: a call that silences the radio through a
// path other than a restriction shows up here as a TurnOff with no restriction line before it.
@wrapMethod(PocketRadio)
private final func TurnOff(playSFX: Bool) -> Void {
  RadioXLLog(s"pocket radio TurnOff(playSFX=\(playSFX)) station=\(this.m_station) restricted=\(this.IsRestricted())");
  wrappedMethod(playSFX);
}

