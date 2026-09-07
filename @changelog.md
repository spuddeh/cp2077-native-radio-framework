# Changelog - Native Radio Framework

## [0.2.0] - 2026-09-08

### Added
- The engine's station NAME table is extended alongside the roster, so a custom station's label is
  a native localization key. Both of its readers reduce the index modulo 14; the division is erased.
- Station name and song titles registered as real localization entries, inserted into
  `onscreens.json` in sorted position under both hash widths.
- `RadioStation` and `UIIcon` TweakDB records built from the manifest in `ScriptableTweak.OnApply`,
  with the index the roster assigned. A station naming no icon gets the game's own `no_station` part.
- The vehicle radio list sorted by the frequency at the front of the display name.
- A per-station DJ through the manifest's `speaker`, defaulting to `None`.
- `plugin/src/Duration.hpp`: each track's length read from the audio file's headers at plugin load
  (MP3 via Xing/Info/VBRI or a frame walk, FLAC, Ogg Vorbis, WAV), exposed as
  `NRF_StationTrackDuration`. A track with no readable length is dropped and logged.

### Fixed
- The station was silent on every receiver when its registration waited for AudioXL to report
  durations: the engine builds its station set while `cooked_metadata` loads, and a station added
  afterwards is never constructed. Event rows, membership, the station entry and the text are now all
  written as their resources load; only the AudioXL registration polls.
- AudioXL routing is `mod_sfx_radio`, the game's own radio route. An `axl_*` type is a 2D sound the
  radio system does not own.
- Natives are registered module-qualified (`NativeRadioFramework.NRF_*`); a bare registration fails
  script validation for every redscript mod on the machine.
- `RED4EXT_HEADER_ONLY` is no longer defined twice (the SDK's `Common.hpp` defines it).


## [0.1.0] - 2026-09-07

### Added
- RED4ext plugin that extends the engine's compiled radio station roster, so a custom station is a
  real station rather than a separate player.
- Vehicle receiver bound raised, so a custom station can be selected in a car.
- Station manifests discovered from `red4ext/plugins/NativeRadioFramework/stations/<Mod>/station.json`.
- Redscript service that registers each station's metadata entry and its membership of the station
  map at runtime.

### Notes
- Nothing vanilla is replaced. No archive ships, so station mods cannot conflict with each other.
