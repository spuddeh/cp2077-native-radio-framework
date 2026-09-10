// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Puts custom stations on the radio dial, in the UI and in the cycling order.
// File Version: 0.3.0
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

module RadioXL

@if(ModuleExists("TweakXL"))
import TweakXL.*

// The default icon for a station that names none: the RadioXL glyph, shipped in the framework's
// own `archive/pc/mod/RadioXL.archive`, one 256x256 part. Nothing vanilla is replaced by it. The
// vanilla station atlas is kept apart because a world device's logo widget is fixed to it and has
// to be pointed back at it for a vanilla station.
//
// **A UIIcon record pointing at an atlas that does not exist fails silently** - the widget keeps
// whatever it was showing, which reads as the previous station's logo.
public class RadioXLIcons {
  public final static func FallbackAtlas() -> String {
    return "radioxl\\gui\\radioxl_icons.inkatlas";
  }

  public final static func FallbackPart() -> String {
    return "radioxl";
  }

  public final static func VanillaAtlas() -> String {
    return "base\\gameplay\\gui\\common\\icons\\radiostations_icons.inkatlas";
  }

  // The record a RadioXL 0.1.0 station yaml names as its icon. Kept so those files stay valid.
  public final static func RecordName() -> String {
    return "UIIcon.RadioXL";
  }
}

public class RadioXLDial {
  // The station's own enum value, or -1 for a vanilla one.
  public final static func Slot(station: Int32) -> Int32 {
    let custom: Int32 = station - 14;
    return custom >= 0 && custom < RadioXL_StationCount() ? custom : -1;
  }

  public final static func Total() -> Int32 {
    return 14 + RadioXL_StationCount();
  }

  // Every record the framework creates is named after the station, so nothing has to be declared in
  // a mod's yaml and no two station mods can collide on a record id.
  public final static func RecordName(slot: Int32) -> String {
    return "RadioStation.RadioXL_" + NameToString(RadioXL_StationName(slot));
  }

  public final static func IconName(slot: Int32) -> String {
    return "UIIcon.RadioXL_" + NameToString(RadioXL_StationName(slot));
  }

  public final static func Record(station: Int32) -> TweakDBID {
    let slot: Int32 = RadioXLDial.Slot(station);
    return slot < 0 ? TDBID.None() : TDBID.Create(RadioXLDial.RecordName(slot));
  }
}

// --- the TweakDB records -------------------------------------------------------------------------
// A station mod ships a manifest, its audio and at most an icon archive. The records the dial needs
// are built here from that manifest, so a mod author never writes a yaml and never has to guess an
// index. **A record's `index` is the station's DIAL POSITION, a UI index, not its enum value**:
// the popup hands `record.Index()` to `SendRadioEvent`, which converts it through
// `GetRadioStationByUIIndex`. Vanilla's records carry 0 for 88.9 up to 13 for 107.5. A custom
// station's position depends on which other station mods are installed, so it is read from the
// plugin's dial at load. Writing the enum value here plays the station one position below.

// **A record is created from a ScriptableTweak, never a ScriptableService.** OnApply is the point
// TweakXL extends TweakDB; anything written before that is discarded when TweakDB loads, which
// leaves the station playing but absent from every list that reads a record.
@if(ModuleExists("TweakXL"))
public class RadioXLRecords extends ScriptableTweak {
  protected cb func OnApply() -> Void {
    this.BuildFrameworkIcon();
    let count: Int32 = RadioXL_StationCount();
    let i: Int32 = 0;
    while i < count {
      this.Build(i);
      i += 1;
    }
    if count > 0 {
      this.Retune();
      RadioXLLog(s"built \(count) station record(s)");
    }
  }

  // The fourteen vanilla records carry their vanilla dial position as `index`, a fixed number. A
  // custom station inserted below one of them moves that station's position, so the record must
  // say the new one, or the popup finds two records on one index: both light up, and selecting
  // either plays whichever station now holds that position. Vanilla order is untouched when no
  // custom station sits inside the dial; the number written is then the number already there.
  // `UIIcon.RadioXL`, the framework's own glyph as a record: the fallback below points at the same
  // atlas and part, and a station yaml written for RadioXL 0.1.0 names this record by id.
  private func BuildFrameworkIcon() -> Void {
    let name: String = RadioXLIcons.RecordName();
    let id: TweakDBID = TDBID.Create(name);
    if IsDefined(TweakDBInterface.GetUIIconRecord(id)) { return; }
    TweakDBManager.CreateRecord(StringToName(name), n"gamedataUIIcon_Record");
    TweakDBManager.SetFlat(TDBID.Create(name + ".atlasPartName"),
                           ToVariant(StringToName(RadioXLIcons.FallbackPart())));
    TweakDBManager.SetFlat(TDBID.Create(name + ".atlasResourcePath"),
                           ToVariant(ResRef.FromName(StringToName(RadioXLIcons.FallbackAtlas()))));
    TweakDBManager.UpdateRecord(id);
  }

  private func Retune() -> Void {
    let names: array<String> = ["AggroIndie", "ElectroIndie", "HipHop", "AggroTechno", "Downtempo", "AttRock", "Pop",
                                "Latino", "Metal", "MinimTech", "Jazz", "GrowlFM", "DarkStar", "Impulse"];
    let station: Int32 = 0;
    while station < 14 {
      let recordName: String = "RadioStation." + names[station];
      let position: Int32 = RadioXL_DialPosition(station);
      if position >= 0 {
        TweakDBManager.SetFlat(TDBID.Create(recordName + ".index"), ToVariant(position));
        TweakDBManager.UpdateRecord(TDBID.Create(recordName));
      }
      station += 1;
    }
  }

  private func Build(slot: Int32) -> Void {
    let iconName: String = RadioXLDial.IconName(slot);
    let iconId: TweakDBID = TDBID.Create(iconName);

    let part: String = RadioXL_StationIcon(slot);
    let atlas: String = RadioXL_StationAtlas(slot);
    if StrLen(part) == 0 {
      part = RadioXLIcons.FallbackPart();
      atlas = RadioXLIcons.FallbackAtlas();
    }
    if StrLen(atlas) == 0 {
      atlas = RadioXLIcons.FallbackAtlas();
    }

    // `atlasResourcePath` is a resource reference, and TweakXL refuses a value of another type
    // outright (`AssignFlat` returns InvalidType) - a String written here is dropped and the record
    // keeps an empty atlas, which makes every icon request fail silently. ResRef.FromName hashes
    // the path the way a depot path is hashed.
    let madeIcon: Bool = TweakDBManager.CreateRecord(StringToName(iconName), n"gamedataUIIcon_Record");
    let setPart: Bool = TweakDBManager.SetFlat(TDBID.Create(iconName + ".atlasPartName"),
                                               ToVariant(StringToName(part)));
    let setAtlas: Bool = TweakDBManager.SetFlat(TDBID.Create(iconName + ".atlasResourcePath"),
                                                ToVariant(ResRef.FromName(StringToName(atlas))));
    TweakDBManager.UpdateRecord(iconId);
    if !setPart || !setAtlas {
      RadioXLLog(s"\(iconName): part \(setPart) atlas \(setAtlas) - the icon record is incomplete");
    }

    // The display name is plain text. The engine's name table holds the station's localization KEY
    // and the popup compares the two resolved strings, so both sides have to land on the same text.
    let recordName: String = RadioXLDial.RecordName(slot);
    let recordId: TweakDBID = TDBID.Create(recordName);
    let madeStation: Bool = TweakDBManager.CreateRecord(StringToName(recordName), n"gamedataRadioStation_Record");
    TweakDBManager.SetFlat(TDBID.Create(recordName + ".displayName"),
                           ToVariant(RadioXL_StationDisplayName(slot)));
    TweakDBManager.SetFlat(TDBID.Create(recordName + ".icon"), ToVariant(iconId));
    let position: Int32 = RadioXL_DialPosition(14 + slot);
    TweakDBManager.SetFlat(TDBID.Create(recordName + ".index"), ToVariant(position));
    TweakDBManager.UpdateRecord(recordId);

    RadioXLLog(s"\(recordName): record \(madeStation), icon \(madeIcon) (\(part) in \(atlas)), dial position \(position)");
  }
}

// Without TweakXL there are no records, so a custom station plays but never reaches the dial.
@if(!ModuleExists("TweakXL"))
public class RadioXLRecordsMissing extends ScriptableService {
  private cb func OnLoad() {
    if RadioXL_StationCount() > 0 {
      RadioXLLog("TweakXL is absent - stations play but cannot appear on the dial");
    }
  }
}

// --- how many stations there are -------------------------------------------------------------------

@wrapMethod(RadioStationDataProvider)
public final static func GetStationsCount() -> Int32 {
  return wrappedMethod() + RadioXL_StationCount();
}

// --- name and channel ------------------------------------------------------------------------------

@wrapMethod(RadioStationDataProvider)
public final static func GetStationName(radioStationType: ERadioStationList) -> CName {
  let slot: Int32 = RadioXLDial.Slot(EnumInt(radioStationType));
  return slot >= 0 ? RadioXL_StationName(slot) : wrappedMethod(radioStationType);
}

// A channel name is a localization key, the same shape vanilla returns. A world device resolves it
// by STRING, which only works for a key inside the game's `Gameplay-` namespace - which the plugin's
// keys are.
@wrapMethod(RadioStationDataProvider)
public final static func GetChannelName(radioStationType: ERadioStationList) -> String {
  let slot: Int32 = RadioXLDial.Slot(EnumInt(radioStationType));
  return slot >= 0 ? NameToString(RadioXL_StationKey(slot)) : wrappedMethod(radioStationType);
}

// --- dial order ---------------------------------------------------------------------------------
// The "UI index" is the DIAL POSITION: vanilla's maps put the fourteen in ascending frequency, and
// the plugin's table does the same for every station, with each custom one inserted at its
// frequency. The plugin owns the order so the vehicle's native step and these agree; the vanilla
// maps are the fallback for an unpatched roster.

@wrapMethod(RadioStationDataProvider)
public final static func GetRadioStationUIIndex(index: Int32) -> Int32 {
  let position: Int32 = RadioXL_DialPosition(index);
  return position >= 0 ? position : wrappedMethod(index);
}

@wrapMethod(RadioStationDataProvider)
public final static func GetRadioStationByUIIndex(index: Int32) -> ERadioStationList {
  let station: Int32 = RadioXL_DialStation(index);
  return station >= 0 ? IntEnum<ERadioStationList>(station) : wrappedMethod(index);
}

// --- cycling -------------------------------------------------------------------------------------
// Replaced rather than wrapped: the vanilla bodies carry `% 14`, which no wrapper can reach.
//
// Vanilla skips Samizdat Radio in both directions, by its position number: the station before it
// steps over it forwards and the station after it steps over it backwards. That is a design
// choice and it is kept, anchored to the station rather than the number, since a custom station
// below 95.2 moves the number.

@replaceMethod(RadioStationDataProvider)
public final static func GetNextStationTo(currentIndex: Int32) -> ERadioStationList {
  let total: Int32 = RadioXLDial.Total();
  let current: Int32 = RadioStationDataProvider.GetRadioStationUIIndex(currentIndex);
  let skip: Int32 = RadioStationDataProvider.GetRadioStationUIIndex(EnumInt(ERadioStationList.MINIMAL_TECHNO));
  current = current == skip - 1 ? skip : current;
  return RadioStationDataProvider.GetRadioStationByUIIndex((current + 1) % total);
}

@replaceMethod(RadioStationDataProvider)
public final static func GetPreviousStationTo(currentIndex: Int32) -> ERadioStationList {
  let total: Int32 = RadioXLDial.Total();
  let current: Int32 = RadioStationDataProvider.GetRadioStationUIIndex(currentIndex);
  let skip: Int32 = RadioStationDataProvider.GetRadioStationUIIndex(EnumInt(ERadioStationList.MINIMAL_TECHNO));
  current = current == skip + 1 ? skip : current;
  return RadioStationDataProvider.GetRadioStationByUIIndex((current - 1 + total) % total);
}

@replaceMethod(RadioStationDataProvider)
public final static func GetNextStationPocketRadio(currentIndex: Int32) -> ERadioStationList {
  if currentIndex == -1 {
    return RadioStationDataProvider.GetRadioStationByUIIndex(0);
  }
  let total: Int32 = RadioXLDial.Total();
  let current: Int32 = RadioStationDataProvider.GetRadioStationUIIndex(currentIndex);
  return RadioStationDataProvider.GetRadioStationByUIIndex((current + 1) % total);
}

// --- the vehicle radio list ----------------------------------------------------------------------
// The popup shows this array in order, and vanilla pushes No Station and then its fourteen in
// dial order: 88.9, 89.3, 89.7, 91.9 and so on. So the list is the dial with one row in front, and
// a custom station goes in at its dial position plus one. Walking the dial in position order keeps
// every index valid as rows are inserted.

@wrapMethod(VehiclesManagerDataHelper)
public final static func GetRadioStations(player: ref<GameObject>) -> array<ref<IScriptable>> {
  let list: array<ref<IScriptable>> = wrappedMethod(player);

  let total: Int32 = RadioXLDial.Total();
  let position: Int32 = 0;
  while position < total {
    let slot: Int32 = RadioXLDial.Slot(RadioXL_DialStation(position));
    if slot >= 0 {
      let record = TweakDBInterface.GetRadioStationRecord(TDBID.Create(RadioXLDial.RecordName(slot)));
      if IsDefined(record) {
        let data = new RadioListItemData();
        data.m_record = record;
        let at: Int32 = position + 1;
        if at < ArraySize(list) {
          ArrayInsert(list, at, data);
        } else {
          ArrayPush(list, data);
        }
      }
    }
    position += 1;
  }
  return list;
}

// --- the world device's station logo -------------------------------------------------------------
// The vanilla body is a switch over the fourteen that sets a texture PART on whatever atlas the
// widget holds, which the .inkwidget fixes to the vanilla station atlas. A custom station's part
// lives in its own atlas, so the widget is pointed at that atlas and the part set the same way. The
// fourteen run the vanilla body untouched, with the vanilla atlas put back first in case a custom
// station replaced it.

@wrapMethod(RadioInkGameController)
private final func SetupStationLogo() -> Void {
  let station: Int32 = EnumInt(this.GetOwner().GetDevicePS().GetActiveRadioStation());
  if RadioXLDial.Slot(station) < 0 {
    inkImageRef.SetAtlasResource(this.m_stationLogoWidget,
                                 ResRef.FromName(StringToName(RadioXLIcons.VanillaAtlas())));
    wrappedMethod();
    return;
  }

  let record = TweakDBInterface.GetRadioStationRecord(RadioXLDial.Record(station));
  let icon = IsDefined(record) ? record.Icon() : null;
  if !IsDefined(icon) {
    wrappedMethod();
    return;
  }
  inkImageRef.SetAtlasResource(this.m_stationLogoWidget, icon.AtlasResourcePath());
  if !inkImageRef.SetTexturePart(this.m_stationLogoWidget, icon.AtlasPartName()) {
    RadioXLLog(s"device logo: part \(icon.AtlasPartName()) is not in the widget's atlas yet");
  }
}
