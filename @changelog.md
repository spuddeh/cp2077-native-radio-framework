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
  stage at world devices. First trimmed to 0.56 in the samples through `AudioXLNative.SetGain`,
  which corrects one receiver at a time: the stereo path needs -4.95 dB and the mono path -3.0.
  The level now comes off the samples entirely - see the routing bank below. New optional manifest
  key `gain` (0..1) and native `NRF_StationGain`. (#3)
- A station's level is a send trim, carried by `red4ext/plugins/NativeRadioFramework/nrf_routing.bnk`
  and the `nrf_radio` custom-sound type it defines: a byte clone of `mod_sfx_radio`'s Event, Play
  action and CAkSound, citing the bank's **own copies** of Radio Vexelstrom's two Broadcast Sends
  (-2.0 dB stereo, -5.0 dB mono) rather than `radio.bnk`'s objects, which a patch could move out
  from under it. Built by `tools/make_routing_bank.py`; every id is FNV-derived from an `nrf_`
  string. `kDefaultGain` is 1.0, and the 0.56 applies only on the `mod_sfx_radio` fallback, where it
  multiplies a station's own gain rather than replacing it. Measured: 0 wrap artefacts in 550 s
  against 6,250 in 160 s, true peak -1.4 dBFS, a custom station inside the vanilla loudness spread.
  Confirmed in game: station switching stops the previous track, a vehicle takes over from the
  Radioport, a world device attenuates with distance, a wanted star ducks and combat stops the audio,
  the Music slider still moves it, WAV tracks play, and the bank survives loading a second save. (#17)
- The custom-sound TYPE gets its own row in the audio event table. AudioXL stores a row's type as the
  CName hash of the type string and the engine resolves that name through `eventsmetadata.json`, so
  a type absent from it plays nothing and reports nothing: the bank loaded, all 84 tracks registered,
  both stations built, every log line read as success, and every station was silent. (#17)
- Each track played twice on world devices: not the LAME gapless trim, which made the declared
  duration *exact* and so put every track on a coin flip. The engine re-posts a slot's track when the
  voice ends while that slot is still current, and the event row holds a 32-bit float whose step is
  15 microseconds at three minutes. Measured on two tracks four microseconds either side of their own
  length: the one rounded up played twice, the one rounded down played once. The row is now written
  at `duration - 0.5 s`, as vanilla does by seconds (`mus_radio_12_afterlife` declares 166 for 169.7).
  Verified over three boundaries at ratios 1.000 and 0.998. (#15)
- The station clock observer (`Clock.reds`) reads a station's position from
  `GetRadioStationCurrentTrackName`, which returns the track's **localization key** rather than its
  event name, resolved through `GetLocalizedTextByKey`. Restarts on every `Session/Ready` with a
  generation retiring the old chain, because a session's delay callbacks do not outlive it and the
  main menu is a session of its own. Instrument only; not for release. (#1)
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
