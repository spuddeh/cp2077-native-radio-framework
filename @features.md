# Feature List - Native Radio Framework

## Implemented

- Custom stations are real engine stations: the compiled roster and station name table are extended
  at plugin load, so the Radioport, world radios and the vehicle radio all play them unwrapped.
- A station is one manifest per mod, plus its audio files and at most an icon archive. Any number of
  station mods coexist; nothing vanilla is replaced and the framework ships no archive.
- Each track's length is read from its file at load, so a station runs on the world clock like a
  vanilla one. No durations, event names, Wwise ids or records in a manifest.
- Station name and song titles are real localization entries, resolved wherever a vanilla one is.
- The station appears on the vehicle radio wheel, sorted by frequency, with its own name and icon.
- An optional DJ per station (`speaker`), defaulting to none.
- An optional level trim per station (`gain`, default 0.56), applied in the samples through AudioXL.
  The default keeps a 0 dBFS master under the rail on the game's custom-radio send at world devices.

## Verified in game (2026-09-08)

- Audio on all three receivers, two stations installed side by side.
- Station name and icon on the Radioport, the vehicle selector, the dashboard and world devices.
- World-device loudness at vanilla level (`distance` 30).

## Awaiting in-game verification (deployed to Testing 2026-09-08)

- No crackle at world devices with the shipped AudioXL and the default `gain` (verified with a probe
  build at 0.25; the shipped path through `SetGain` is the same code).
- Each track plays once at a world device (one boundary verified).
- Song titles outside the Radioport. The DJ.

## Planned

- Resume where a vanilla station would when switching away and back. Measured: the engine hands no
  offset on the custom-sound path, so the framework must compute one from its durations and the
  station clock and pass it to AudioXL as a per-row start (#1).
- Vehicle next/previous cycling past the vanilla fourteen (`0x25fdf1b` is unpatched).
- Replace the two roster functions and the vehicle receiver rather than patching their bounds, which
  lifts the 127-station ceiling.
- Adopt RadioXL station definitions unchanged, starting with Outrun Waves 93.7.
- Build a station in game from any installed song.
