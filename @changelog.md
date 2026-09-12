# Changelog - RadioXL

## [0.3.0] - 2026-09-11

### Changed
- Renamed from Native Radio Framework to RadioXL: the framework takes over DigitalVixen's RadioXL
  name and Nexus page (33488) from the 0.1.0 script player. Plugin `RadioXL.dll`, redscript module
  `RadioXL`, natives `RadioXL_*`, records `RadioStation.RadioXL_<name>` / `UIIcon.RadioXL_<name>`,
  localization keys `...-RadioXL-<name>`, custom-sound type `radioxl_radio` in `radioxl_routing.bnk`
  (rebuilt; ids are FNV of the new strings), station manifests under
  `red4ext/plugins/RadioXL/stations/`. GitHub repo `spuddeh/cp2077-radio-xl`.
- AudioXL 0.3.0 is the minimum. It streams compressed tracks of 45 s or more from disk, which
  removes the resident-PCM cost that made WAV the recommendation (#4), and adds `PlayFrom`,
  `Position`, `IsPlaying` and `Pause`.

### Fixed
- Toggling a vehicle radio off and on while on a custom station landed on a random vanilla one
  (#27). The receiver's turn-on block treats a stored station at or past 14 as none chosen; the
  bound is raised to the station total with the other three. The block has no RED4ext hash, so
  the plugin follows the enable routine's own `jne` to it and verifies the bytes there.

### Added
- Shuffle (#22): a four-way setting (Off, Every station, Vanilla only, Custom only), read by the
  plugin from RCF's own file at boot because RCF restores settings after the metadata has loaded;
  the script reorders vanilla `tracks` arrays as the base and EP1 metadata load, the plugin
  reorders custom stations as manifests are read. A manifest's `shuffle` is three-valued: `true`
  always, `false` never, absent follows the setting. Measured: a session-time reorder is ignored,
  so it takes effect on the next launch. DJ song nodes post by name and are unaffected.
- The mute switches apply to every station on the Radioport, vanilla included, and a switch is a
  situation: a lifted switch also lifts the companion restrictions its situation raises. Measured
  sets: a holo call brings `BlockFastTravel` and `QuestContentLock`; a vehicle scene brings
  `PhoneNoCalling`, `UpperBodyState` and the skip prompt; a scene brings `UpperBodyState` and the
  skip prompt. A wrap on `OnStatusEffectApplied` records every tag an effect carries before the
  game walks them, so the first companion already sees its situation and the radio never drops
  for the unlock delay. Every hint names its trigger in the game's code and its default; tab text
  is a `Label` row, since a `Tip` attaches to the last row built.
- Resume on tune-back (#1), from the engine's own station clock. The engine posts a custom track
  from 0 and hands no offset; the station object's clock (`+0x14c`) counts seconds since its slot
  began, on engine time, whether or not anyone listens. `plugin/src/Clock.hpp` reads it four times
  a second from the plugin's game-state update, asks the engine which track the station is on
  (`GetRadioStationCurrentTrackName`, matched by the track's localization key), and arms that row
  through AudioXL's `PlayFrom` over RTTI. Replaces `Clock.reds`, a DelaySystem watch that wrote the
  playing voice's position back each tick: the station selector on foot stops sim time while it is
  open, the watch stopped with it, and the second station picked from an open selector started from
  0. Verified in game: a tune-back lands at the station clock and swaps from an open selector resume.
- "Mute radio when..." (`Settings.reds`, `Restrictions.reds`): twelve switches in the Redscript
  Configuration Framework panel, one per `PocketRadioRestrictions` member, all on by default. Off
  lifts that restriction for a custom station only, through a wrap of `PocketRadio.HandleRestriction`
  that records the world's value and hands the pocket radio the switched one; a `TurnOn` wrap gives a
  vanilla station the restriction back. RCF is optional; without it the defaults apply. Combat and
  police heat, RadioXL 0.1.0's other two switches, are Wwise mix states on the radio buses and have no
  switch on the game's own radio route.
- The RadioXL glyph as the fallback icon (#18): `archive/pc/mod/RadioXL.archive` (DV's, one 256x256
  part) replaces the game's `no_station` part, and `UIIcon.RadioXL` is created at `OnApply` so a
  RadioXL 0.1.0 station yaml naming it stays valid. The vanilla atlas is still put back on a world
  device's logo widget for a vanilla station.
- `RadioXLAPI.RegisterStation(name)`: a RadioXL 0.1.0 station's script compiles and is logged rather
  than failing script validation for every redscript mod on the machine. The station is not created;
  adopting the old shape is #10.
- `r6/storages/RedscriptConfigFramework/RadioXL.card.json` and `RadioXL.docs.txt`: the RCF card and
  the in-game documentation, written for the framework.

## [0.2.0] - 2026-09-08

### Added
- `plugin/src/Json.hpp` and `plugin/src/Manifest.hpp`: the manifest is read by a strict JSON parser
  (RFC 8259 plus a byte-order mark; no comments, trailing commas or single quotes) and checked field
  by field. Every fault is logged as `<Mod>/station.json:<line>: <what>`, a syntax fault with its
  column too, and a manifest with one is skipped whole. Refused: `name` missing or outside
  `[A-Za-z0-9_]`, `tracks` missing, empty or not an array, a track with no `file`, a `speaker` the
  game does not have, `gain` not a number, `icon` without `atlas`. Logged and ignored: an unknown
  key, `gain` outside 0..1, `atlas` without `icon`. Replaces the substring scanner, which read a
  title containing `"file"` as the file and stopped an array at a `]` inside a title.
  `plugin/tests/ManifestTests.cpp` covers one case per rule, run by `ctest`. (#8)
- The vehicle receiver's next-station step is detoured. The block at `+0x68..+0x92` of the
  set-station function maps the current index through a dial-order switch on 0..13, adds one modulo
  14, and maps back through the inverse switch; both switches misanswer a custom index and the
  remainder is used, so neither erasing nor retuning the division works. The 42 bytes become a `jmp`
  to a 55-byte stub, allocated within rip-relative reach and made executable before any game byte
  is written, that calls the game's own switches for the fourteen, uses the slot index as the dial
  position past them, and takes the total as a 32-bit immediate. Eight more bytes verified first;
  the stub's call targets are read from the verified block. The dial order the switches encode is
  88.9 to 107.5. (#7)
- The plugin owns the dial order. `BuildDial` asks the game's switch for the fourteen's order at
  patch time, then inserts each custom station before the first station whose frequency is above
  the number at the front of its display name, against the fourteen vanilla frequencies in
  `kVanillaFrequency`; a station with no number goes last. The next-station stub reads two tables
  behind its code (`position[total]`, `dial[total]`) instead of calling the switches, and two new
  natives, `RadioXL_DialPosition` and `RadioXL_DialStation`, hand the same tables to `Dial.reds`:
  `GetRadioStationUIIndex` / `GetRadioStationByUIIndex` map every station through them, the
  cycling replacements keep vanilla's Samizdat skip anchored to the station rather than position
  5, and the vehicle list inserts a custom station at its dial position plus one. One order on
  every receiver. (#14)
- A `RadioStation` record's `index` is written as the station's dial position, not its enum
  value. The popup hands `record.Index()` to `SendRadioEvent`, which converts it through
  `GetRadioStationByUIIndex`, so the field is a UI index; vanilla carries 0 for 88.9 to 13 for
  107.5. The enum value equalled the position only while custom stations were appended, and the
  first station inserted inside the vanilla dial made every station above it play the content of
  the one below. (#14)
- The fourteen vanilla `RadioStation` records are rewritten to their new dial positions at load.
  Their `index` flats are fixed vanilla positions, so a custom station inserted below one left two
  records on one index: the popup lit both and selecting either played the station now holding
  that position. Measured with a station at 97.5: it and Body Heat both lit and both played it,
  Tool FM at 104.9 and Morro Rock did the same, and every vanilla station above played the
  station one position below. (#14)
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
  `RadioXL_StationTrackDuration`. A track with no readable length is dropped and logged.

### Fixed
- Every rip-relative displacement the roster patch writes is range-checked before the cast, and the
  patch is abandoned if one does not fit. Each table is allocated within reach of one reader; the
  other reader of the same table was only in reach by the layout of the 2.31 image. (#11)
- World-device crackle: `mod_sfx_radio`'s stereo Broadcast Send is trimmed +2.9 dB where every
  vanilla station sits between -4 and +0.9 dB, so a master on 0 dBFS wrapped in the next 16-bit
  stage at world devices. First trimmed to 0.56 in the samples through `AudioXLNative.SetGain`,
  which corrects one receiver at a time: the stereo path needs -4.95 dB and the mono path -3.0.
  The level now comes off the samples entirely - see the routing bank below. New optional manifest
  key `gain` (0..1) and native `RadioXL_StationGain`. (#3)
- A station's level is a send trim, carried by `red4ext/plugins/RadioXL/radioxl_routing.bnk`
  and the `radioxl_radio` custom-sound type it defines: a byte clone of `mod_sfx_radio`'s Event, Play
  action and CAkSound, citing the bank's **own copies** of Radio Vexelstrom's two Broadcast Sends
  (-2.0 dB stereo, -5.0 dB mono) rather than `radio.bnk`'s objects, which a patch could move out
  from under it. Built by `tools/make_routing_bank.py`; every id is FNV-derived from an `radioxl_`
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
- Natives are registered module-qualified (`RadioXL.RadioXL_*`); a bare registration fails
  script validation for every redscript mod on the machine.
- `RED4EXT_HEADER_ONLY` is no longer defined twice (the SDK's `Common.hpp` defines it).


## [0.1.0] - 2026-09-07

### Added
- RED4ext plugin that extends the engine's compiled radio station roster, so a custom station is a
  real station rather than a separate player.
- Vehicle receiver bound raised, so a custom station can be selected in a car.
- Station manifests discovered from `red4ext/plugins/RadioXL/stations/<Mod>/station.json`.
- Redscript service that registers each station's metadata entry and its membership of the station
  map at runtime.

### Notes
- Nothing vanilla is replaced. No archive ships, so station mods cannot conflict with each other.
