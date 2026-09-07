// ======================================================================================
// Mod Name: Native Radio Framework
// Author: Spuddeh
// Description: Puts custom stations on the radio dial, in the UI and in the cycling order.
// File Version: 0.1.0
// Credits: RED4ext by WopsS.
// ======================================================================================
//
// The engine plays a custom station once its identity is in the roster. The DIAL is a separate
// problem and an entirely script-side one: `RadioStationDataProvider` holds the fourteen vanilla
// stations in five hardcoded switch maps, and `VehiclesManagerDataHelper` pushes fifteen literal
// TweakDB record ids. Neither knows about anything past the vanilla set.
//
// A custom station's enum value is its roster slot: the first one is 14, the next 15, and so on.
// Its UI index is the same number, so custom stations sit after the vanilla fourteen on the dial in
// the order they were discovered.
//
// **Three of these are @replaceMethod and that is deliberate.** The cycling functions carry `% 14`
// inside them, so wrapping cannot reach the modulus. It also means this framework is an alternative
// to RadioExt and RadioXL rather than a companion - all three rewrite the same functions.

module NativeRadioFramework

@if(ModuleExists("TweakXL"))
import TweakXL.*

// The record's `index` is what the vehicle radio popup plays: it calls
// `SendRadioEvent(true, true, data.m_record.Index())` and compares the current station against it.
// So a station's index MUST equal the roster slot the plugin gave it, and that slot depends on how
// many station mods are installed and in what order they were discovered.
//
// A station mod therefore cannot know its own index when it writes its yaml. The framework assigns
// it here instead, and whatever the yaml says is overwritten.
@if(ModuleExists("TweakXL"))
public class NRFIndex extends ScriptableService {
  private cb func OnLoad() {
    let count: Int32 = NRF_StationCount();
    let i: Int32 = 0;
    while i < count {
      let path: String = NRF_StationRecord(i);
      if StrLen(path) > 0 {
        let slot: Int32 = 14 + i;
        TweakDBManager.SetFlat(TDBID.Create(path + ".index"), ToVariant(slot));
        TweakDBManager.UpdateRecord(TDBID.Create(path));
        NRFLog(s"\(path) index set to \(slot)");
      }
      i += 1;
    }
  }
}

// Without TweakXL a station keeps whatever index its yaml declared, which is only correct when it
// is the sole station installed. Its record could not have been created without TweakXL either.
@if(!ModuleExists("TweakXL"))
public class NRFIndex extends ScriptableService {
  private cb func OnLoad() {
    NRFLog("TweakXL is absent - station indices are left as declared, which breaks with more than one station mod");
  }
}

public class NRFDial {
  // The station's own enum value, or -1 for a vanilla one.
  public final static func Slot(station: Int32) -> Int32 {
    let custom: Int32 = station - 14;
    return custom >= 0 && custom < NRF_StationCount() ? custom : -1;
  }

  public final static func Total() -> Int32 {
    return 14 + NRF_StationCount();
  }

  public final static func Record(station: Int32) -> TweakDBID {
    let slot: Int32 = NRFDial.Slot(station);
    if slot < 0 { return TDBID.None(); }
    let path: String = NRF_StationRecord(slot);
    return StrLen(path) > 0 ? TDBID.Create(path) : TDBID.None();
  }
}

// --- how many stations there are ---------------------------------------------------------------

@wrapMethod(RadioStationDataProvider)
public final static func GetStationsCount() -> Int32 {
  return wrappedMethod() + NRF_StationCount();
}

// --- name and channel --------------------------------------------------------------------------

@wrapMethod(RadioStationDataProvider)
public final static func GetStationName(radioStationType: ERadioStationList) -> CName {
  let slot: Int32 = NRFDial.Slot(EnumInt(radioStationType));
  if slot >= 0 {
    NRFLog(s"GetStationName(\(EnumInt(radioStationType))) -> \(NRF_StationName(slot))");
    return NRF_StationName(slot);
  }
  return wrappedMethod(radioStationType);
}

// The channel name is a localisation key, shown by device radios. A custom station has no vanilla
// key, so it borrows its own record's display name.
@wrapMethod(RadioStationDataProvider)
public final static func GetChannelName(radioStationType: ERadioStationList) -> String {
  let station: Int32 = EnumInt(radioStationType);
  if NRFDial.Slot(station) >= 0 {
    let record = TweakDBInterface.GetRadioStationRecord(NRFDial.Record(station));
    if IsDefined(record) {
      return GetLocalizedText(record.DisplayName());
    }
    return "";
  }
  return wrappedMethod(radioStationType);
}

// --- dial order ---------------------------------------------------------------------------------
// Custom stations sit after the vanilla fourteen, so enum value and UI index are the same number.

@wrapMethod(RadioStationDataProvider)
public final static func GetRadioStationUIIndex(index: Int32) -> Int32 {
  if NRFDial.Slot(index) >= 0 {
    return index;
  }
  return wrappedMethod(index);
}

@wrapMethod(RadioStationDataProvider)
public final static func GetRadioStationByUIIndex(index: Int32) -> ERadioStationList {
  if NRFDial.Slot(index) >= 0 {
    return IntEnum<ERadioStationList>(index);
  }
  return wrappedMethod(index);
}

// --- cycling -------------------------------------------------------------------------------------
// Replaced rather than wrapped: the vanilla bodies carry `% 14`, which no wrapper can reach.

@replaceMethod(RadioStationDataProvider)
public final static func GetNextStationTo(currentIndex: Int32) -> ERadioStationList {
  let total: Int32 = NRFDial.Total();
  let current: Int32 = RadioStationDataProvider.GetRadioStationUIIndex(currentIndex);
  // Minimal Techno is skipped going forwards in the vanilla body, and that is a design choice
  // rather than an accident, so it is kept.
  current = current == 4 ? 5 : current;
  return RadioStationDataProvider.GetRadioStationByUIIndex((current + 1) % total);
}

@replaceMethod(RadioStationDataProvider)
public final static func GetPreviousStationTo(currentIndex: Int32) -> ERadioStationList {
  let total: Int32 = NRFDial.Total();
  let current: Int32 = RadioStationDataProvider.GetRadioStationUIIndex(currentIndex);
  current = current == 6 ? 5 : current;
  return RadioStationDataProvider.GetRadioStationByUIIndex((current - 1 + total) % total);
}

@replaceMethod(RadioStationDataProvider)
public final static func GetNextStationPocketRadio(currentIndex: Int32) -> ERadioStationList {
  if currentIndex == -1 {
    return RadioStationDataProvider.GetRadioStationByUIIndex(0);
  }
  let total: Int32 = NRFDial.Total();
  let current: Int32 = RadioStationDataProvider.GetRadioStationUIIndex(currentIndex);
  return RadioStationDataProvider.GetRadioStationByUIIndex((current + 1) % total);
}

// --- the vehicle radio list ----------------------------------------------------------------------
// The popup shows this array in order, and vanilla pushes its fifteen in ascending frequency:
// 88.9, 89.3, 89.7, 91.9 and so on, after No Station. So a custom station is inserted at its
// frequency rather than appended, or it sits at the bottom of a dial that is otherwise a real dial.
//
// The frequency is the front of the display name - the game has no field for it.

public class NRFFreq {
  public final static func Of(record: wref<RadioStation_Record>) -> Float {
    if !IsDefined(record) { return -1.0; }
    let head: String;
    let tail: String;
    if !StrSplitFirst(GetLocalizedText(record.DisplayName()), " ", head, tail) {
      return -1.0;
    }
    return StringToFloat(head, -1.0);
  }
}

@wrapMethod(VehiclesManagerDataHelper)
public final static func GetRadioStations(player: ref<GameObject>) -> array<ref<IScriptable>> {
  let list: array<ref<IScriptable>> = wrappedMethod(player);

  let count: Int32 = NRF_StationCount();
  let i: Int32 = 0;
  while i < count {
    let id: TweakDBID = NRFDial.Record(14 + i);
    if TDBID.IsValid(id) {
      let record = TweakDBInterface.GetRadioStationRecord(id);
      if IsDefined(record) {
        let data = new RadioListItemData();
        data.m_record = record;

        let ours: Float = NRFFreq.Of(record);
        let at: Int32 = -1;
        let j: Int32 = 0;
        while j < ArraySize(list) {
          let row = list[j] as RadioListItemData;
          // No Station has no frequency and parses as -1, so it always stays first.
          if at < 0 && IsDefined(row) && NRFFreq.Of(row.m_record) > ours {
            at = j;
          }
          j += 1;
        }
        if at < 0 {
          ArrayPush(list, data);
        } else {
          ArrayInsert(list, at, data);
        }
      }
    }
    i += 1;
  }
  return list;
}

// --- the world device's station logo -------------------------------------------------------------
// SetupStationLogo is a switch over the fourteen that falls through to "no_station", and it only
// sets the texture PART - the widget keeps the vanilla atlas. A custom station needs both: its own
// atlas resource and its own part, taken from the UIIcon record its station record points at.

@wrapMethod(RadioInkGameController)
private final func SetupStationLogo() -> Void {
  let station: Int32 = EnumInt(this.GetOwner().GetDevicePS().GetActiveRadioStation());
  if NRFDial.Slot(station) < 0 {
    wrappedMethod();
    return;
  }

  let stationRecord = TweakDBInterface.GetRadioStationRecord(NRFDial.Record(station));
  if !IsDefined(stationRecord) {
    wrappedMethod();
    return;
  }
  // The vehicle popup already solves this: given a UIIcon record id, RequestSetImage loads the
  // record's own atlas and part. Setting the part alone would leave the vanilla atlas in place.
  InkImageUtils.RequestSetImage(this, this.m_stationLogoWidget, stationRecord.Icon().GetID(), n"");
  NRFLog(s"device logo: station \(station) -> \(stationRecord.Icon().GetID())");
}

// --- the dashboard station label -------------------------------------------------------------
// `GetRadioReceiverStationName` is native with NO SCRIPT BODY, so it cannot be wrapped, and on a
// custom station it falls back to AGGRO_INDUSTRIAL - Radio Vexelstrom. The station itself is
// right: `GetCurrentRadioIndex` returns the real slot. So the name is corrected where it is
// written and where it is read, and a vanilla station is never touched.

@addMethod(VehicleComponent)
private final func NRFFixStationName() -> Void {
  let vehicle: wref<VehicleObject> = this.GetVehicle();
  if !IsDefined(vehicle) || !IsDefined(this.m_vehicleBlackboard) {
    return;
  }
  let slot: Int32 = NRFDial.Slot(Cast<Int32>(vehicle.GetCurrentRadioIndex()));
  if slot < 0 {
    return;
  }
  this.m_vehicleBlackboard.SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName,
                                   NRF_StationName(slot));
}

@wrapMethod(VehicleComponent)
protected cb func OnVehicleRadioStationInitialized(evt: ref<VehicleRadioStationInitialized>) -> Bool {
  let handled: Bool = wrappedMethod(evt);
  this.NRFFixStationName();
  return handled;
}

@wrapMethod(VehicleComponent)
protected cb func OnVehicleRadioEvent(evt: ref<VehicleRadioEvent>) -> Bool {
  let handled: Bool = wrappedMethod(evt);
  this.NRFFixStationName();
  return handled;
}

// The popup reads the same native directly rather than the blackboard.
@wrapMethod(VehicleRadioPopupGameController)
private final func GetRadioReceiverStationName() -> CName {
  if IsDefined(this.m_playerVehicle) {
    let slot: Int32 = NRFDial.Slot(Cast<Int32>(this.m_playerVehicle.GetCurrentRadioIndex()));
    if slot >= 0 {
      return NRF_StationName(slot);
    }
  }
  return wrappedMethod();
}

// --- song titles ----------------------------------------------------------------------------
// A vanilla track name is a localization key and the popup calls SetLocalizedText with it. A
// custom station's titles are plain text in the manifest, so they are substituted here rather
// than registered as strings the game would have to look up.
//
// The lookup is by track EVENT name, which is what the receiver reports, so it does not depend on
// knowing which station is playing.

public class NRFTitle {
  public final static func Of(event: CName) -> String {
    if !IsNameValid(event) {
      return "";
    }
    let station: Int32 = 0;
    let count: Int32 = NRF_StationCount();
    while station < count {
      let tracks: Int32 = NRF_StationTrackCount(station);
      let t: Int32 = 0;
      while t < tracks {
        if Equals(NRF_StationTrack(station, t), event) {
          return NRF_StationTrackTitle(station, t);
        }
        t += 1;
      }
      station += 1;
    }
    return "";
  }
}

@wrapMethod(VehicleRadioPopupGameController)
private final func SetTrackName(track: CName) -> Void {
  let title: String = NRFTitle.Of(track);
  if StrLen(title) > 0 {
    inkTextRef.SetText(this.m_trackName, title);
    inkWidgetRef.SetVisible(this.m_trackName, true);
    return;
  }
  wrappedMethod(track);
}
