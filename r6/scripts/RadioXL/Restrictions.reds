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
  // **A switch is a situation, and a situation raises more than one restriction.** Measured:
  //   a holo call     raises BlockFastTravel and QuestContentLock beside PhoneCall
  //   a vehicle scene raises PhoneNoCalling and UpperBodyState beside VehicleScene
  // Lifting the situation's own restriction alone leaves the radio silenced by its companions, so
  // while a situation is up and its switch is off, its companions are lifted with it. A companion
  // raised on its own, by a quest, still mutes as its own switch says. Situations not yet measured
  // have no companions here and their switch lifts only the restriction it names.
  public static func Companions(situation: Int32) -> array<Int32> {
    if situation == EnumInt(PocketRadioRestrictions.PhoneCall) {
      return [EnumInt(PocketRadioRestrictions.BlockFastTravel), EnumInt(PocketRadioRestrictions.QuestContentLock)];
    }
    if situation == EnumInt(PocketRadioRestrictions.VehicleScene) {
      return [EnumInt(PocketRadioRestrictions.PhoneNoCalling), EnumInt(PocketRadioRestrictions.UpperBodyState)];
    }
    let none: array<Int32>;
    return none;
  }

  public static func IsCompanionOfLifted(restriction: Int32) -> Bool {
    let cfg = RadioXLConfig.Get();
    let state = RadioXLRestrictions.Get();
    if !IsDefined(cfg) || !IsDefined(state) { return false; }
    let situations: array<Int32> = [EnumInt(PocketRadioRestrictions.PhoneCall), EnumInt(PocketRadioRestrictions.VehicleScene)];
    let i: Int32 = 0;
    while i < ArraySize(situations) {
      let s: Int32 = situations[i];
      if state.Actual(s) && !cfg.MutesOn(s) && ArrayContains(RadioXLRestrictions.Companions(s), restriction) {
        return true;
      }
      i += 1;
    }
    return false;
  }

  public static func Applied(restriction: Int32, restricted: Bool, station: Int32) -> Bool {
    if !restricted { return restricted; }
    let cfg = RadioXLConfig.Get();
    if !IsDefined(cfg) { return true; }
    if !cfg.MutesOn(restriction) { return false; }
    return !RadioXLRestrictions.IsCompanionOfLifted(restriction);
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

// **One status effect carries every restriction a situation raises, and the game applies them one
// tag at a time in a fixed order.** A holo call's effect carries the quest lock, the fast-travel
// block and the call, and the call is walked last, so on its own each companion would be applied
// before the call is known and the radio would drop out for the unlock delay. Recording every tag
// the effect carries BEFORE the game walks them lets the first companion see the call already.
@wrapMethod(PocketRadio)
public final func OnStatusEffectApplied(evt: ref<ApplyStatusEffectEvent>, gameplayTags: script_ref<[CName]>) -> Void {
  let state = RadioXLRestrictions.Get();
  if IsDefined(state) {
    if ArrayContains(Deref(gameplayTags), n"InDaClub") { state.Record(EnumInt(PocketRadioRestrictions.InDaClub), true); }
    if ArrayContains(Deref(gameplayTags), n"BlockFastTravel") { state.Record(EnumInt(PocketRadioRestrictions.BlockFastTravel), true); }
    if ArrayContains(Deref(gameplayTags), n"VehicleScene") { state.Record(EnumInt(PocketRadioRestrictions.VehicleScene), true); }
    if ArrayContains(Deref(gameplayTags), n"VehicleBlockPocketRadio") { state.Record(EnumInt(PocketRadioRestrictions.VehicleBlockPocketRadio), true); }
    if ArrayContains(Deref(gameplayTags), n"PhoneCall") { state.Record(EnumInt(PocketRadioRestrictions.PhoneCall), true); }
    if ArrayContains(Deref(gameplayTags), n"PhoneNoTexting") { state.Record(EnumInt(PocketRadioRestrictions.PhoneNoTexting), true); }
    if ArrayContains(Deref(gameplayTags), n"PhoneNoCalling") { state.Record(EnumInt(PocketRadioRestrictions.PhoneNoCalling), true); }
    if ArrayContains(Deref(gameplayTags), n"FastForward") { state.Record(EnumInt(PocketRadioRestrictions.FastForward), true); }
    if ArrayContains(Deref(gameplayTags), n"FastForwardHintActive") { state.Record(EnumInt(PocketRadioRestrictions.FastForwardHintActive), true); }
  }
  wrappedMethod(evt, gameplayTags);
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
  // A companion that arrived before its situation was applied on its own switch. Now that the
  // situation is known, hand each its situation-aware value. The re-entry records the same actual
  // and cannot loop, because a companion is never a situation.
  if IsDefined(state) {
    let companions: array<Int32> = RadioXLRestrictions.Companions(EnumInt(restriction));
    let i: Int32 = 0;
    while i < ArraySize(companions) {
      let c: Int32 = companions[i];
      if state.Actual(c) && !Equals(this.m_restrictions[c], RadioXLRestrictions.Applied(c, true, this.m_selectedStation)) {
        this.HandleRestriction(IntEnum<PocketRadioRestrictions>(c), true);
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

