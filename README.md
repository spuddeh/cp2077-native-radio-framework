# RadioXL

A custom radio station for Cyberpunk 2077 that is a **real engine station**, not a mod-authored music
player. The engine's station roster is a fixed 14-slot array compiled into the binary. RadioExt
ships FMOD and RadioXL 0.1.0 recreated the radio in script, and both reach only the receivers they
wrap. This framework extends that array instead, so a custom station plays on the Radioport, the
vehicle radio and world device radios through the game's own radio system, with nothing wrapped
around them.

**This is RadioXL from 0.3.0 on.** DigitalVixen's RadioXL 0.1.0, the script player on the same
[Nexus page](https://www.nexusmods.com/cyberpunk2077/mods/33488), is what it replaces; the name and
the page carry over, the audio side stays DigitalVixen's in AudioXL, and a station written for
0.1.0 is converted to the manifest below (its script still compiles and the log names it).

**Status: in development.** Two stations play on every receiver with their own names and icons;
what is still open is in the [issues](https://github.com/spuddeh/cp2077-radio-xl/issues), with what
has been measured on each.

## What a station mod ships

One manifest, its audio files, and at most an icon archive:

```text
red4ext/plugins/RadioXL/stations/<YourMod>/station.json
red4ext/plugins/RadioXL/stations/<YourMod>/audio/*.mp3
archive/pc/mod/<YourMod>.archive          (optional - the station icon)
```

```json
{
  "name": "radio_station_20_tool",
  "displayName": "104.9 Tool FM",
  "icon": "tool_fm",
  "atlas": "toolfm\\gui\\tool_fm.inkatlas",
  "speaker": "Ash",
  "tracks": [
    { "file": "audio/Tool - Vicarious.mp3", "title": "Tool - Vicarious" },
    { "file": "audio/Tool - Jambi.mp3",     "title": "Tool - Jambi" }
  ]
}
```

No durations, event names, Wwise ids, indices, TweakDB records, yaml or redscript. The framework
derives or reads all of it. The full field reference is
[stations/README.md](red4ext/plugins/RadioXL/stations/README.md), which ships with the
framework so the `stations/` folder survives packaging.

## Requirements

- [RED4ext](https://www.nexusmods.com/cyberpunk2077/mods/2380)
- [redscript](https://www.nexusmods.com/cyberpunk2077/mods/1511)
- [Codeware](https://www.nexusmods.com/cyberpunk2077/mods/7780) - resource callbacks and localization
- [AudioXL](https://www.nexusmods.com/cyberpunk2077/mods/33442) 0.3.0 or later - plays the audio
  files, streams long tracks from disk, and carries the per-row start offset a resume needs
- [TweakXL](https://www.nexusmods.com/cyberpunk2077/mods/4197) - the station's records for the dial

Optional: [Redscript Configuration Framework](https://www.nexusmods.com/cyberpunk2077/mods/30726)
shows the settings panel; without it the defaults apply.
[RedLogger](https://www.nexusmods.com/cyberpunk2077/mods/31920): with it installed the framework
writes what it registered to `r6/logs/mods/`; without it the logging compiles away.

## Settings

**Mute radio when...** - twelve switches, all on by default, one per situation in which the game
silences the pocket radio (a scene, a phone call, a club, fast travel and so on). On, a custom
station goes quiet there as a vanilla station does. Off, a custom station keeps playing through it.
The game's own stations are never affected. Combat and police heat have no switch: they are Wwise
mix states on the radio buses and reach every station on the game's radio route alike.

## How it works

What the framework measured about the engine on the way - the compiled roster and its readers, the
boot-time window a station must be registered in, why every label is a key, what `mod_sfx_radio`
is and what AudioXL's renderer does with it - is written up in [docs/](docs/README.md), each claim
marked measured or inferred.

Several of those measurements are numbers a game patch can move, and none of them fails loudly.
[MAINTAINING.md](MAINTAINING.md) is the list of what to re-derive and how to tell it has gone wrong.

Three layers. The split matters, because each one extends a different engine system.

### The plugin - `plugin/src/`

A RED4ext plugin. At load it reads every station manifest, reads each track's length from the audio
file's headers (`Duration.hpp`: MP3, FLAC, Ogg Vorbis, WAV, nothing decoded), and **patches the
binary before any script runs**:

| Table | Holds | Patched sites |
| --- | --- | --- |
| the station roster, 14 `CName` slots | a station's identity | name-to-index and index-to-name readers, and the vehicle receiver's bound |
| the station name table, 14 `CName` slots | a station's label as a localization key | two readers, each of which reduces the index modulo 14; the division is erased |
| the vehicle receiver's next-station step | which station a car steps to | detoured to a stub reading the plugin's own dial tables, because the step runs the index through two dial-order switches on 0..13 around a modulo 14 |

Addresses resolve through RED4ext's shipped hash database, never hardcoded. Every byte is verified
first and the whole patch is abandoned on a single mismatch, because a half-patched radio system is
worse than an unpatched one. Both bounds are 8-bit immediates, so 127 stations is the ceiling.

A station manifest is read by a strict JSON parser and checked field by field. Every fault is logged
with the file and the line, and a manifest with one is skipped whole rather than half-loaded.

The plugin exposes the manifest to redscript through registered natives (`RadioXL_Station*`). It does
not touch audio, TweakDB or UI.

### `RadioXL.reds` - assembly, as the resources load

Three of the game's own resources are patched **while they load**, because the engine builds its
station set once, at boot, and anything added afterwards is never constructed:

| Resource | What is added |
| --- | --- |
| `eventsmetadata.json` | one event row per track, carrying its duration |
| `cooked_metadata.audio_metadata` | membership in `radioStations`, an `audioRadioStationMetadata`, an `audioRadioTrack` per title |
| `onscreens.json` | the station name and every song title, inserted in sorted position under both hash widths |

Every label the game shows is a localization key, never text. The framework mints a key per station
and per title and registers the text against it, so the UI resolves a custom station the way it
resolves a vanilla one.

`Audio.reds` is the only place the framework talks to AudioXL: it registers each file on the game's
`mod_sfx_radio` route, the type CDPR built for custom radio audio, and asks AudioXL for the Wwise id.

### `Dial.reds` - records and the script-side dial

Creates the `RadioStation` and `UIIcon` TweakDB records from the manifest at load, with the index the
roster assigned, and wraps the game's redscript where the fourteen stations are written into switch
bodies and a literal array push. Three cycling functions are replaced rather than wrapped because
their bodies carry `% 14`. That makes this framework an alternative to RadioExt and RadioXL, not a
companion.

## Building the plugin

Header-only against [RED4ext.SDK](https://github.com/WopsS/RED4ext.SDK). The CMake file expects the
SDK at `../../../_source/RED4ext.SDK/include`; point `target_include_directories` at your own copy.

```powershell
cmake -S plugin -B plugin\build -G "Visual Studio 17 2022" -A x64
cmake --build plugin\build --config Release
Copy-Item plugin\build\Release\RadioXL.dll red4ext\plugins\RadioXL\
```

The SDK's exports are version-qualified (`RED4ext::v1::PluginInfo`, `RED4EXT_V1_SEMVER`).

## Design rules

- **Extend what the engine already stores. Never mimic it.** If a label is wrong, find the table the
  engine reads and extend it; do not wrap the UI to substitute a string.
- **Wrap only where no table exists.** `RadioStationDataProvider` and `VehiclesManagerDataHelper`
  hold the fourteen as literals, with nothing behind them to extend.
- **No parallel audio path.** A station is a voice on the game's own radio emitter. A sound played
  alongside the radio is wrong even when it is audible.
- **The manifest is the whole station.** Nothing a modder has to compute goes in it.

## Known limits

- The DLL and the scripts ship together, always. A `.reds` that declares natives fails script
  validation without its plugin, and that stops every redscript mod on the machine.
- Three `@replaceMethod` on the cycling functions, so RadioExt and RadioXL cannot coexist with it.

## Repository layout

```text
plugin/src/Main.cpp          the binary patch, the natives
plugin/src/Json.hpp          a strict JSON reader, every fault by line and column
plugin/src/Manifest.hpp      the manifest checks, every fault by file and line
plugin/src/Duration.hpp      a track's length from its file headers
plugin/tests/                the manifest reader's tests, run by ctest
r6/scripts/RadioXL/
  RadioXL.reds  the three resource patches
  Audio.reds                 the AudioXL bridge
  Dial.reds                  TweakDB records and the script-side dial
red4ext/plugins/RadioXL/
  RadioXL.dll   the built plugin
  stations/README.md         the manifest reference, ships with the framework
```

The worked example, Tool FM, is a manifest and eleven MP3s. Its audio is a personal copy of a
commercial album and is never distributed, so that repository stays private; the manifest above is
its manifest.

## License

[MIT](LICENSE). Take what is useful.

## Credits

RED4ext by WopsS. AudioXL and RadioXL by DigitalVixen. Codeware, TweakXL and ArchiveXL by psiberx.

## Disclaimer

This mod was developed with the assistance of an LLM. All in-game testing and code validation was
performed by a human. No rogue AIs were permitted through the Blackwall.
