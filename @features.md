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

## Awaiting in-game verification (deployed to Testing 2026-09-08)

- Audio on all three receivers after the load-order fix.
- Continues where a vanilla station would when switching away and back.
- Station name on the in-car stereo and world devices; icon on the dial and world devices.
- Song titles outside the Radioport. Two station mods installed side by side.

## Planned

- Vehicle next/previous cycling past the vanilla fourteen (`0x25fdf1b` is unpatched).
- Replace the two roster functions and the vehicle receiver rather than patching their bounds, which
  lifts the 127-station ceiling.
- Adopt RadioXL station definitions unchanged, starting with Outrun Waves 93.7.
- Build a station in game from any installed song.
