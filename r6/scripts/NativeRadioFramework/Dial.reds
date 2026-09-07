// ======================================================================================
// Mod Name: Native Radio Framework
// Author: Spuddeh
// Description: Puts custom stations on the radio dial, in the UI and in the cycling order.
// File Version: 0.2.0
// Credits: RED4ext by WopsS.
// ======================================================================================
//
// The engine plays a custom station once its identity is in the roster, and it LABELS one once the
// name table holds its key. The DIAL is a third problem and an entirely script-side one:
// `RadioStationDataProvider` holds the fourteen vanilla stations in hardcoded switch maps, and
// `VehiclesManagerDataHelper` pushes fifteen literal TweakDB record ids. Neither has a table behind
// it to extend, so these are wrapped - and that is the only reason anything here is a wrapper.
//
// A custom station's enum value is its roster slot: the first is 14, the next 15, and so on.
//
// **Three of these are @replaceMethod and that is deliberate.** The cycling functions carry `% 14`
// inside them, so wrapping cannot reach the modulus. It also means this framework is an alternative
// to RadioExt and RadioXL rather than a companion - all three rewrite the same functions.

module NativeRadioFramework

@if(ModuleExists("TweakXL"))
import TweakXL.*

// The framework's own atlas, used by a station that names no icon of its own.
public class NRFIcons {
  public final static func FallbackAtlas() -> String {
    return "nativeradioframework\\gui\\stations.inkatlas";
  }

  public final static func FallbackPart() -> String {
    return "nrf_default";
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

  // Every record the framework creates is named after the station, so nothing has to be declared in
  // a mod's yaml and no two station mods can collide on a record id.
  public final static func RecordName(slot: Int32) -> String {
    return "RadioStation.NRF_" + NameToString(NRF_StationName(slot));
  }

  public final static func IconName(slot: Int32) -> String {
    return "UIIcon.NRF_" + NameToString(NRF_StationName(slot));
  }

  public final static func Record(station: Int32) -> TweakDBID {
    let slot: Int32 = NRFDial.Slot(station);
    return slot < 0 ? TDBID.None() : TDBID.Create(NRFDial.RecordName(slot));
  }
}

// --- the TweakDB records -------------------------------------------------------------------------
// A station mod ships a manifest, its audio and at most an icon archive. The records the dial needs
// are built here from that manifest, so a mod author never writes a yaml and never has to guess an
// index: the index MUST equal the roster slot the plugin assigned, and that depends on how many
// station mods are installed and in what order they were found.

@if(ModuleExists("TweakXL"))
public class NRFRecords extends ScriptableService {
  private cb func OnLoad() {
    let count: Int32 = NRF_StationCount();
    let i: Int32 = 0;
    while i < count {
      this.Build(i);
      i += 1;
    }
    if count > 0 {
      NRFLog(s"built \(count) station record(s)");
    }
  }

  private func Build(slot: Int32) -> Void {
    let iconName: String = NRFDial.IconName(slot);
    let iconId: TweakDBID = TDBID.Create(iconName);

    let part: String = NRF_StationIcon(slot);
    let atlas: String = NRF_StationAtlas(slot);
    if StrLen(part) == 0 {
      part = NRFIcons.FallbackPart();
      atlas = NRFIcons.FallbackAtlas();
    }
    if StrLen(atlas) == 0 {
      atlas = NRFIcons.FallbackAtlas();
    }

    TweakDBManager.CreateRecord(StringToName(iconName), n"gamedataUIIcon_Record");
    TweakDBManager.SetFlat(TDBID.Create(iconName + ".atlasPartName"), ToVariant(StringToName(part)));
    TweakDBManager.SetFlat(TDBID.Create(iconName + ".atlasResourcePath"), ToVariant(atlas));
    TweakDBManager.UpdateRecord(iconId);

    // The display name is plain text. The engine's name table holds the station's localization KEY
    // and the popup compares the two resolved strings, so both sides have to land on the same text.
    let recordName: String = NRFDial.RecordName(slot);
    let recordId: TweakDBID = TDBID.Create(recordName);
    TweakDBManager.CreateRecord(StringToName(recordName), n"gamedataRadioStation_Record");
    TweakDBManager.SetFlat(TDBID.Create(recordName + ".displayName"),
                           ToVariant(NRF_StationDisplayName(slot)));
    TweakDBManager.SetFlat(TDBID.Create(recordName + ".icon"), ToVariant(iconId));
    TweakDBManager.SetFlat(TDBID.Create(recordName + ".index"), ToVariant(14 + slot));
    TweakDBManager.UpdateRecord(recordId);
  }
}

// Without TweakXL there are no records, so a custom station plays but never reaches the dial.
@if(!ModuleExists("TweakXL"))
public class NRFRecords extends ScriptableService {
  private cb func OnLoad() {
    if NRF_StationCount() > 0 {
      NRFLog("TweakXL is absent - stations play but cannot appear on the dial");
    }
  }
}

// --- how many stations there are -------------------------------------------------------------------

@wrapMethod(RadioStationDataProvider)
public final static func GetStationsCount() -> Int32 {
  return wrappedMethod() + NRF_StationCount();
}

// --- name and channel ------------------------------------------------------------------------------

@wrapMethod(RadioStationDataProvider)
public final static func GetStationName(radioStationType: ERadioStationList) -> CName {
  let slot: Int32 = NRFDial.Slot(EnumInt(radioStationType));
  return slot >= 0 ? NRF_StationName(slot) : wrappedMethod(radioStationType);
}

// A channel name is a localization KEY, and a custom station has one minted for it.
@wrapMethod(RadioStationDataProvider)
public final static func GetChannelName(radioStationType: ERadioStationList) -> String {
  let slot: Int32 = NRFDial.Slot(EnumInt(radioStationType));
  return slot >= 0 ? NameToString(NRF_StationKey(slot)) : wrappedMethod(radioStationType);
}

// --- dial order ---------------------------------------------------------------------------------
// Custom stations sit after the vanilla fourteen, so enum value and UI index are the same number.

@wrapMethod(RadioStationDataProvider)
public final static func GetRadioStationUIIndex(index: Int32) -> Int32 {
  return NRFDial.Slot(index) >= 0 ? index : wrappedMethod(index);
}

@wrapMethod(RadioStationDataProvider)
public final static func GetRadioStationByUIIndex(index: Int32) -> ERadioStationList {
  return NRFDial.Slot(index) >= 0 ? IntEnum<ERadioStationList>(index) : wrappedMethod(index);
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
    let record = TweakDBInterface.GetRadioStationRecord(TDBID.Create(NRFDial.RecordName(i)));
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
}
