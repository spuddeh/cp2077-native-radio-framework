// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The script API a RadioXL 0.1.0 station mod calls.
// File Version: 0.3.0
// ======================================================================================
//
// A station built for RadioXL 0.1.0 registers itself with one call from its own script. That call
// has to exist, or the station mod fails script validation and takes every redscript mod on the
// machine down with it. Adopting such a station outright - reading its record and its AudioXL
// rows as a manifest - is issue #10; until then the call is answered and logged, and the station
// is not created.

module RadioXL

public class RadioXLAPI {
  public final static func RegisterStation(name: String) -> Void {
    RadioXLLog(s"RegisterStation(\"\(name)\"): a RadioXL 0.1.0 station definition. A station.json manifest is what makes it play; adopting the old shape unchanged is issue #10");
  }
}
