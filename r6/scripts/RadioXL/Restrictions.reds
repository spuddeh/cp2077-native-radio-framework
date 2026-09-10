// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Keeps a custom station playing through a situation the player chose not to mute in.
// File Version: 0.3.0
// ======================================================================================
//
// The game silences the pocket radio through `PocketRadio.HandleRestriction`: each restriction is
// recorded, and while any is set the radio is turned off and every tune request is ignored. A
// custom station is a real station, so it is silenced the same way. **A switch that is off lifts
// that one restriction, for a custom station only**: the restriction is recorded as clear while a
// custom station is selected, and as set again the moment a vanilla station is. The world's own
// value of each restriction is kept here, so a station change or a switch change can re-apply it.
//
// Combat and police heat never pass through this class. They are Wwise mix states on the radio
// buses and reach every station alike; see Settings.reds.

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
  public static func Applied(restriction: Int32, restricted: Bool, station: Int32) -> Bool {
    if !restricted || RadioXLDial.Slot(station) < 0 { return restricted; }
    let cfg = RadioXLConfig.Get();
    return !IsDefined(cfg) || cfg.MutesOn(restriction);
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
  wrappedMethod(restriction, RadioXLRestrictions.Applied(EnumInt(restriction), restricted, this.m_selectedStation));
}

// A vanilla station selected while a lifted restriction is still in force gets the restriction
// back, so the switches never reach the game's own stations.
@wrapMethod(PocketRadio)
private final func TurnOn(playSFX: Bool) -> Void {
  wrappedMethod(playSFX);
  let state = RadioXLRestrictions.Get();
  if !IsDefined(state) || RadioXLDial.Slot(this.m_station) >= 0 { return; }
  let i: Int32 = 0;
  while i < EnumInt(PocketRadioRestrictions.PocketRadioRestrictionCount) {
    if state.Actual(i) && !this.m_restrictions[i] {
      this.HandleRestriction(IntEnum<PocketRadioRestrictions>(i), true);
    }
    i += 1;
  }
}
