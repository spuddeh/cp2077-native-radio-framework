// ======================================================================================
// Mod Name: Native Radio Framework
// Author: Spuddeh
// Description: Registers the station name and song titles through Codeware's localization system.
// File Version: 0.2.0
// Credits: Codeware by psiberx.
// ======================================================================================
//
// A row inserted into onscreens.json as it loads resolves by numeric hash, which is how a song title
// is looked up, and does not resolve by key STRING, which is how `GetLocalizedTextByKey` and
// `inkText.SetLocalizedTextString` look a station name up - the dashboard and every world device.
// Codeware merges provider text at the engine's own text-loading hook, and text registered there
// resolves both ways. The keys are the same ones the plugin mints, so the two routes agree.

module NativeRadioFramework

// Codeware is a hard dependency of the framework (the callback system, the resource depot,
// ScriptableService), so this import is unconditional.
import Codeware.Localization.*

// The same package for every language: a station's name and titles are the modder's text as
// written, not translated. Codeware asks for the fallback and the current language and merges both.
public class NRFLocalizationProvider extends ModLocalizationProvider {
  public func GetPackage(language: CName) -> ref<ModLocalizationPackage> {
    return new NRFTexts();
  }

  public func GetFallback() -> CName {
    return n"en-us";
  }
}

public class NRFTexts extends ModLocalizationPackage {
  protected func DefineTexts() -> Void {
    let added: Int32 = 0;
    let station: Int32 = 0;
    let count: Int32 = NRF_StationCount();
    while station < count {
      let name: String = NRF_StationDisplayName(station);
      if StrLen(name) > 0 {
        this.Text(NameToString(NRF_StationKey(station)), name);
        added += 1;
      }
      let tracks: Int32 = NRF_StationTrackCount(station);
      let t: Int32 = 0;
      while t < tracks {
        let title: String = NRF_StationTrackTitle(station, t);
        if StrLen(title) > 0 {
          this.Text(NameToString(NRF_StationTrackKey(station, t)), title);
          added += 1;
        }
        t += 1;
      }
      station += 1;
    }
    NRFLog(s"handed \(added) string(s) to Codeware's localization system");
  }
}
