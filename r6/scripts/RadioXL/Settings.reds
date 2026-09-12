// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The player's settings - which of the game's radio silences a custom station keeps.
// File Version: 0.3.0
// Credits: Redscript Configuration Framework by DigitalVixen.
// ======================================================================================
//
// A custom station is a real station, so every rule that silences the pocket radio silences it
// too: a scene, a phone call, a club, fast travel and the rest, exactly as they silence a vanilla
// station. These switches let the player keep a CUSTOM station playing through a situation the
// game would silence it in. Every switch is on by default, which is the game's own behaviour, and
// a vanilla station is never affected whichever way a switch is set.
//
// **Combat and police heat are not here.** The game ducks and stops the radio in those through
// the Wwise mix state on the radio buses, which a station on the game's own radio route cannot
// opt out of. RadioXL 0.1.0 could offer them because its sound was a 2D event of its own.
//
// Redscript Configuration Framework is optional. Without it the defaults apply and there is no
// panel; with it the panel is the "RadioXL" card.

module RadioXL

@if(ModuleExists("RedscriptConfigFramework"))
import RedscriptConfigFramework.*

public class RadioXLConfig extends ScriptableSystem {

  public static func Get() -> ref<RadioXLConfig> {
    return GameInstance.GetScriptableSystemsContainer(GetGameInstance())
      .Get(n"RadioXL.RadioXLConfig") as RadioXLConfig;
  }

  // One per PocketRadioRestrictions member, in enum order.
  public let muteSceneTier: Bool = true;
  public let muteUpperBodyState: Bool = true;
  public let muteQuestContentLock: Bool = true;
  public let muteInDaClub: Bool = true;
  public let muteBlockFastTravel: Bool = true;
  public let muteVehicleScene: Bool = true;
  public let muteVehicleBlockPocketRadio: Bool = true;
  public let mutePhoneCall: Bool = true;
  public let mutePhoneNoTexting: Bool = true;
  public let mutePhoneNoCalling: Bool = true;
  public let muteFastForward: Bool = true;
  public let muteFastForwardHintActive: Bool = true;

  // Every station, the game's fourteen included, plays its tracks in a new random order each
  // launch. Off by default. Read by the plugin from RCF's file at boot, so it takes effect on the
  // next launch, never the current one.
  public let shuffleAll: Bool = false;

  // Whether the game's own silence for this restriction is kept for a custom station.
  public func MutesOn(restriction: Int32) -> Bool {
    if restriction == EnumInt(PocketRadioRestrictions.SceneTier) { return this.muteSceneTier; }
    if restriction == EnumInt(PocketRadioRestrictions.UpperBodyState) { return this.muteUpperBodyState; }
    if restriction == EnumInt(PocketRadioRestrictions.QuestContentLock) { return this.muteQuestContentLock; }
    if restriction == EnumInt(PocketRadioRestrictions.InDaClub) { return this.muteInDaClub; }
    if restriction == EnumInt(PocketRadioRestrictions.BlockFastTravel) { return this.muteBlockFastTravel; }
    if restriction == EnumInt(PocketRadioRestrictions.VehicleScene) { return this.muteVehicleScene; }
    if restriction == EnumInt(PocketRadioRestrictions.VehicleBlockPocketRadio) { return this.muteVehicleBlockPocketRadio; }
    if restriction == EnumInt(PocketRadioRestrictions.PhoneCall) { return this.mutePhoneCall; }
    if restriction == EnumInt(PocketRadioRestrictions.PhoneNoTexting) { return this.mutePhoneNoTexting; }
    if restriction == EnumInt(PocketRadioRestrictions.PhoneNoCalling) { return this.mutePhoneNoCalling; }
    if restriction == EnumInt(PocketRadioRestrictions.FastForward) { return this.muteFastForward; }
    if restriction == EnumInt(PocketRadioRestrictions.FastForwardHintActive) { return this.muteFastForwardHintActive; }
    return true;
  }

  @if(ModuleExists("RedscriptConfigFramework"))
  private let m_provider: ref<RadioXLConfigProvider>;

  @if(ModuleExists("RedscriptConfigFramework"))
  private func OnAttach() -> Void {
    let gi: GameInstance = this.GetGameInstance();
    this.m_provider = new RadioXLConfigProvider();
    this.m_provider.Init(this);
    DVRCF_Store.RestoreInto(gi, "RadioXL", this.m_provider, this.m_provider.BuildSchema());
    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Session/Ready", this, n"OnSessionReady")
      .SetLifetime(CallbackLifetime.Forever);
  }

  @if(ModuleExists("RedscriptConfigFramework"))
  protected cb func OnSessionReady(event: ref<GameSessionEvent>) -> Void {
    if IsDefined(this.m_provider) {
      DVRCF.Register(this.GetGameInstance(), "RadioXL", "RadioXL",
        "Custom radio stations as real stations of the game's own radio.", this.m_provider);
    }
  }
}

@if(ModuleExists("RedscriptConfigFramework"))
public class RadioXLConfigProvider extends DVRCF_Provider {
  private let m_cfg: wref<RadioXLConfig>;

  public func Init(cfg: ref<RadioXLConfig>) -> Void {
    this.m_cfg = cfg;
  }

  public func BuildSchema() -> ref<DVRCF_Schema> {
    let b: ref<DVRCF_SchemaBuilder> = DVRCF_SchemaBuilder.New("RadioXL");

    // **A Tip attaches to the LAST row built, whatever it is.** A tip written straight after a Tab
    // lands on the previous tab's last switch, or on nothing. Text that belongs to a tab is a Label.
    b.Tab("Playback");
    b.Toggle("shuffleAll", "Shuffle every station");
    b.Tip("Default: off. Every station plays its tracks in the order they were written, which is what the game does. On: every station, the game's own fourteen included, plays its tracks in a new random order each time the game starts.");
    b.Label("Takes effect on the next launch of the game.");

    b.Tab("Mute radio when...");
    b.Label("Every switch is on by default. On: the radio goes quiet in that situation, exactly as the game does. Off: a RadioXL station keeps playing through it. The game's own stations are never affected.");
    b.Toggle("muteSceneTier", "A scene is playing");
    b.Tip("Default: on. Any scripted scene, from a conversation that takes some control away up to a full cutscene.");
    b.Toggle("mutePhoneCall", "A holo call is in progress");
    b.Tip("Default: on. From the moment a call connects until it ends.");
    b.Toggle("muteQuestContentLock", "A quest has blocked the radio");
    b.Tip("Default: on. A story moment in which the quest switches the radio off outright.");
    b.Toggle("muteInDaClub", "You are inside a club");
    b.Tip("Default: on. Clubs play their own music.");
    b.Toggle("muteVehicleScene", "A vehicle scene is playing");
    b.Tip("Default: on. A scripted scene inside a vehicle, such as a ride where a character talks to you.");
    b.Toggle("muteVehicleBlockPocketRadio", "The vehicle blocks the Radioport");
    b.Tip("Default: on. A vehicle set to switch the Radioport off during its ride.");
    b.Toggle("muteUpperBodyState", "Your hands are forced empty");
    b.Tip("Default: on. Carrying a body, or a scripted moment that takes your weapons away.");
    b.Toggle("muteBlockFastTravel", "Fast travel is blocked");
    b.Tip("Default: on. A quest state in which the game also disables fast travel.");
    b.Toggle("mutePhoneNoTexting", "Texting is blocked");
    b.Tip("Default: on. A story moment in which the game has disabled text messages.");
    b.Toggle("mutePhoneNoCalling", "Calling is blocked");
    b.Tip("Default: on. A story moment in which the game has disabled holo calls.");
    b.Toggle("muteFastForward", "A scene is being skipped");
    b.Tip("Default: on. A scene or ride is being fast-forwarded with the hold-to-skip control.");
    b.Toggle("muteFastForwardHintActive", "The skip prompt is on screen");
    b.Tip("Default: on. The game is offering to skip a scene or ride: the hold-to-skip prompt is showing.");
    b.Label("Combat and police heat have no switch. They are the game's own mix rules and apply to every station.");

    return b.Build();
  }

  public func GetBool(key: String) -> Bool {
    let c: wref<RadioXLConfig> = this.m_cfg;
    if !IsDefined(c) { return true; }
    if Equals(key, "muteSceneTier") { return c.muteSceneTier; }
    if Equals(key, "muteUpperBodyState") { return c.muteUpperBodyState; }
    if Equals(key, "muteQuestContentLock") { return c.muteQuestContentLock; }
    if Equals(key, "muteInDaClub") { return c.muteInDaClub; }
    if Equals(key, "muteBlockFastTravel") { return c.muteBlockFastTravel; }
    if Equals(key, "muteVehicleScene") { return c.muteVehicleScene; }
    if Equals(key, "muteVehicleBlockPocketRadio") { return c.muteVehicleBlockPocketRadio; }
    if Equals(key, "mutePhoneCall") { return c.mutePhoneCall; }
    if Equals(key, "mutePhoneNoTexting") { return c.mutePhoneNoTexting; }
    if Equals(key, "mutePhoneNoCalling") { return c.mutePhoneNoCalling; }
    if Equals(key, "muteFastForward") { return c.muteFastForward; }
    if Equals(key, "muteFastForwardHintActive") { return c.muteFastForwardHintActive; }
    if Equals(key, "shuffleAll") { return c.shuffleAll; }
    return true;
  }

  public func SetBool(key: String, value: Bool) -> Void {
    let c: wref<RadioXLConfig> = this.m_cfg;
    if !IsDefined(c) { return; }
    if Equals(key, "muteSceneTier") { c.muteSceneTier = value; }
    if Equals(key, "muteUpperBodyState") { c.muteUpperBodyState = value; }
    if Equals(key, "muteQuestContentLock") { c.muteQuestContentLock = value; }
    if Equals(key, "muteInDaClub") { c.muteInDaClub = value; }
    if Equals(key, "muteBlockFastTravel") { c.muteBlockFastTravel = value; }
    if Equals(key, "muteVehicleScene") { c.muteVehicleScene = value; }
    if Equals(key, "muteVehicleBlockPocketRadio") { c.muteVehicleBlockPocketRadio = value; }
    if Equals(key, "mutePhoneCall") { c.mutePhoneCall = value; }
    if Equals(key, "mutePhoneNoTexting") { c.mutePhoneNoTexting = value; }
    if Equals(key, "mutePhoneNoCalling") { c.mutePhoneNoCalling = value; }
    if Equals(key, "muteFastForward") { c.muteFastForward = value; }
    if Equals(key, "muteFastForwardHintActive") { c.muteFastForwardHintActive = value; }
    if Equals(key, "shuffleAll") { c.shuffleAll = value; }

    // A switch changed while a restriction is in force takes effect now, not at the next scene.
    RadioXLRestrictions.Refresh();
  }
}
