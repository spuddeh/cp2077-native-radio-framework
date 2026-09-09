# The manifest, and what is derived from it

A station mod ships a manifest, its audio files and at most an icon archive. Everything else a
station needs is either derived from the manifest or read from the engine at load, so no modder
computes a value the game already knows, and nothing in a manifest can disagree with a file.

## The manifest

```json
{
  "name": "radio_station_20_tool",
  "displayName": "104.9 Tool FM",
  "icon": "tool_fm",
  "atlas": "toolfm\\gui\\tool_fm.inkatlas",
  "speaker": "Ash",
  "tracks": [
    { "file": "audio/Tool - Vicarious.mp3", "title": "Tool - Vicarious" }
  ]
}
```

| Field | What it is |
| --- | --- |
| `name` | the station's `CName`, letters, digits and underscores only, because it is also an event-name prefix and a TweakDB record id. Unique across every installed station mod; first found wins, the log names the loser |
| `displayName` | plain text. **The frequency at the front**, because the game has no field for it: the number decides the station's place on the dial, in the vehicle list and in every receiver's next/previous order. A name with no number at the front puts the station after every station that has one |
| `speaker` | optional DJ: `Stanley`, `MaximumMike`, `Ash`, `Kurtz`, `PoliceDispatch`. Default `None`, which plays |
| `gain` | optional level trim on the samples, 0 to 1, clamped. Default 0.56 (-5 dB), which lands the custom sound's two Broadcast Sends inside the vanilla per-station range; see `audio-path.md`. Applied through AudioXL's `SetGain` once the row exists, because `RegisterSoundEx`'s gain never reaches the samples |
| `icon` / `atlas` | optional inkatlas part and the atlas holding it. Default: the game's own `no_station` part in `base\gameplay\gui\common\icons\radiostations_icons.inkatlas` |
| `tracks[].file` | an audio file relative to the manifest's folder: WAV, MP3, OGG, FLAC |
| `tracks[].title` | optional plain text, shown as written |

Manifests live at `red4ext/plugins/NativeRadioFramework/stations/<Mod>/station.json`, one folder
per mod so nothing is shared. Mod managers discard empty directories, so `stations/` ships a
README to survive packaging.

## How the manifest is read

The manifest is the one file a station author writes by hand, so it is the one input that will be
malformed. `plugin/src/Json.hpp` is a strict reader of RFC 8259 JSON plus a leading byte-order mark:
no comments, no trailing commas, no single quotes, and every fault is reported as the line and
column of the first one with a sentence saying what was expected. `plugin/src/Manifest.hpp` then
checks the tree field by field and logs every fault as `<Mod>/station.json:<line>: <what>`.

**A manifest with a fault is skipped whole.** A station loaded with one field missing looks like a
bug somewhere else, and the log line is the whole of what the author needs.

| Refused | Logged and ignored |
| --- | --- |
| `name` missing, not a string, or holding a character outside `[A-Za-z0-9_]` | a key the framework does not know, at top level or in a track |
| `tracks` missing, not an array, or empty; a track that is not an object or has no `file` | `gain` outside 0 to 1, clamped |
| `speaker` not one of the six the game has | `atlas` with no `icon` |
| `gain` not a number; `icon` with no `atlas` | |

`plugin/tests/ManifestTests.cpp` holds one case per row and runs under `ctest`.

## Everything derived

| Value | Derived as | Why not in the manifest |
| --- | --- | --- |
| roster slot, `ERadioStationList` value | 14 + the order the manifest was found in | depends on which other station mods are installed |
| dial position | every station sorted by frequency, the fourteen in the game's own order | the same reason, and it is what makes a car, a world device and the pocket radio agree |
| internal station id | slot + 8 | an engine bias, see the [roster page](compiled-station-roster.md) |
| track event name | `<name>_NN`, two digits from 01 | a filename with a space or an accent must never reach an event name |
| Wwise id of the event | FNV-1 32-bit of the lowercased event name, from AudioXL | it is a function of the name |
| track duration | read from the file's headers at plugin load | the file is the only thing that can be right; see [station set](station-set-and-load-order.md) |
| station label key | `Gameplay-Devices-Radio-NRF-<name>` | the engine's name table holds a key, and a key resolves by string only under `Gameplay-`, `UI-` or `Common-`; see [localization](localization-keys.md) |
| title key | `Gameplay-Devices-Radio_tracks-NRF-<name>-NN` | `audioRadioTrack` holds a key, in the same namespace as vanilla track keys |
| both hashes of each key | FNV1a32 keeping the key text, FNV1a64 with it cleared | how `onscreens` rows are found; see [localization](localization-keys.md) |
| `RadioStation` record | `RadioStation.NRF_<name>` with `displayName`, `icon`, `index` = slot | the index must equal the roster slot: the popup plays `record.Index()` |
| `UIIcon` record | `UIIcon.NRF_<name>` with `atlasPartName`, `atlasResourcePath` | the wheel and the device logo load atlas and part from it |

`[M]` TweakDB records must be created from `ScriptableTweak.OnApply`, never from a
`ScriptableService`. Records written earlier do not survive TweakDB load, and the station then plays
but appears in no list.

## Cross-station guarantees

- **Slots never collide**, because one plugin assigns them in one pass.
- **Record ids never collide**, because they carry the station name.
- **Event names never collide**, because they carry the station name, and AudioXL's registry is
  first-registered-wins by name across every mod, so a prefix on `name` is the modder's one duty.
- **Nothing vanilla is replaced and the framework ships no archive.** Two station mods cannot
  conflict on a file.

## The script side, and what it wraps

The plugin hands the manifest to redscript through registered natives, `NRF_Station*`. `[M]` A native
declared inside `module X` must be registered as `X.Name`; registered bare it fails script validation
with *Missing native global function*, and **that stops every redscript mod on the machine from
compiling**. The same blast radius applies if the `.reds` is installed without the DLL, so the two
ship as one archive, always.

`RadioStationDataProvider` (station count, name, channel name, UI index both ways) and
`VehiclesManagerDataHelper.GetRadioStations` are game redscript holding the fourteen as switch
bodies and a literal push, with no table behind them. They are wrapped with `@wrapMethod`; custom
stations sit after the vanilla fourteen so enum value and UI index are the same number.

The three cycling functions (`GetNextStationTo`, `GetPreviousStationTo`,
`GetNextStationPocketRadio`) carry `% 14` in their bodies, so they are `@replaceMethod`. Vanilla is
asymmetric there and the replacements keep it: going forward, UI index 4 is mapped to 5; going back,
6 is mapped to 5. This is also why the framework cannot coexist with RadioExt or RadioXL, which
replace the same functions.

`[M]` The vehicle radio list is frequency-ordered. Vanilla pushes No Station and then its fourteen
in dial order (88.9, 89.3, 89.7 …), so the list is the dial with one row in front, and a custom
station is inserted at its dial position plus one. The cycling functions and the vehicle's native
next-station step read the same dial, so every receiver steps through the stations in one order,
with vanilla's skip of Samizdat Radio kept and anchored to the station rather than its number.

`[M]` `RadioInkGameController.SetupStationLogo` (the world device) sets only the texture part on a
widget that already has the vanilla atlas. A custom station needs both atlas and part, which
`InkImageUtils.RequestSetImage` with the `UIIcon` record id supplies. Whether that lands is open
([#6](https://github.com/spuddeh/cp2077-native-radio-framework/issues/6)).

## Icon assets

`[M]` The vanilla station atlas is 1008x1184, `TEXG_Generic_UI` / `TRF_TrueColor` /
`TCM_QualityColor`, no mipchain, parts roughly 240 to 400 px wide. `inkatlas.textureResolution` is an
enum string (`UltraHD_3840_2160`), not a number. A station mod's icon archive uses paths with no
`base\` prefix (`toolfm\gui\tool_fm.xbm`); WolvenKit warns about this, and the warning is wrong for a
UI asset referenced by depot path from a TweakDB record.
