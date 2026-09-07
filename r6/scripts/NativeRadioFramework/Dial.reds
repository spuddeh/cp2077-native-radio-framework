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
// Vanilla pushes fifteen literal record ids. Appending is enough; the popup sorts by the record.

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
        ArrayPush(list, data);
      }
    }
    i += 1;
  }
  return list;
}
