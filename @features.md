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
- A station's level is a send trim, the way every vanilla station's is: the framework loads its own
  bank, defining the `nrf_radio` custom-sound type carrying copies of a vanilla station's two
  Broadcast Sends. No game file is replaced, and the game's own `mod_sfx_radio` type remains the
  fallback if the bank does not load.
- An optional level trim per station (`gain`, 0..1), applied in the samples through AudioXL on top of
  the send trim.
- A manifest is read by a strict JSON parser and checked field by field. Every fault is logged with
  the file and the line, and a manifest with one is skipped whole. Covered by `plugin/tests/`.
- One dial on every receiver: a custom station sits at the frequency at the front of its display
  name, between the vanilla stations, in the vehicle list and in the next/previous order of a car,
  a world device and the pocket radio.

## Verified in game

- Audio on all three receivers, two stations installed side by side, MP3 and WAV tracks.
- Station name and icon on the Radioport, the vehicle selector, the dashboard and world devices.
- No crackle at a world device: 0 wrap artefacts in 550 s of capture, true peak -1.4 dBFS, a custom
  station inside the vanilla loudness spread.
- Each track plays once, over three slot boundaries.
- The radio system owns the sound: switching station stops the previous track, a vehicle takes the
  station over from the Radioport, a world device attenuates with distance, a wanted star ducks the
  audio and combat stops it, and the Music slider moves it.
- The routing bank survives loading a second save without restarting.
- One dial on every receiver: a custom station at 104.9 sits between 103.5 and 106.9 in a car, on a
  world radio and in the vehicle list, and cycling wraps at the end of the roster. World radios skip
  Samizdat as vanilla does; cars and the pocket radio reach it.

## Awaiting in-game verification

- The Radioport level against a vanilla station, by capture rather than by ear.
- Song titles outside the Radioport.

## Planned

- Resume where a vanilla station would when switching away and back. Measured: the engine hands no
  offset on the custom-sound path, so the framework must compute one from its durations and the
  station clock and pass it to AudioXL as a per-row start (#1).
- A `blips` array per station, the engine's own field for a spoken station ident between songs. A
  custom station currently has no way to name itself, and an ident placed in `tracks` is shown as a
  song title and takes a rotation slot.
- Station idents and ads aside, the only vanilla DJ a custom station could reuse is Stanley, whose
  227 lines name no station. His announcements target a selector the engine resolves, and declaring
  `speaker: Stanley` does not reach it (#16).
- Replace the two roster readers rather than patching their bounds, which lifts the 127-station
  ceiling. The vehicle step already carries a 32-bit total.
- Adopt RadioXL station definitions unchanged, starting with Outrun Waves 93.7.
- Build a station in game from any installed song.
