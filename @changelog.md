# Changelog - Native Radio Framework

## [0.2.0] - 2026-09-08

### Added
- `tools/audioxl-feed-probe.patch`: the AudioXL measurement build behind #1, #3 and #15. Logs how the
  engine pulls from `AudioFeed::Execute`, the slot position at voice start and every retire.
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
- World-device crackle: `mod_sfx_radio`'s stereo Broadcast Send is trimmed +2.9 dB where every
  vanilla station sits between -4 and +0.9 dB, so a master on 0 dBFS wrapped in the next 16-bit
  stage at world devices. Every row is now trimmed to 0.56 through `AudioXLNative.SetGain` after
  registration (`RegisterSoundEx`'s gain argument never reaches the samples), with a bounded retry
  for a row AudioXL queued. New optional manifest key `gain` (0..1) and native `NRF_StationGain`.
  Measured: gain 0.25 in the samples took 8,128 half-scale jumps in 160 s to 0. (#3)
- Each track played twice on world devices: `Duration.hpp` counted the raw Xing frame count while
  dr_mp3 trims the LAME gapless delay and padding, so the voice ended 27 to 47 ms inside its own
  slot and the engine re-posted the same track. The reader now subtracts the trim with dr_mp3's
  arithmetic. (#15)
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
