# Maintaining this framework across a game patch

This framework reads the game's own structures and cites some of them by number. A patch can move any
of it. **Nothing here fails loudly**, so this page is the list of things to check rather than a list
of things that will report themselves.

Work top to bottom. The first three are the ones that break a station outright.

## 1. The binary roster patch

`plugin/src/Main.cpp` extends two 14-slot tables, erases a modulo, and detours the vehicle
receiver's next-station step to a stub of its own. Addresses resolve by RED4ext hash, never by
hardcoded RVA, and **the plugin verifies every byte before writing any of them and abandons the
whole patch on a single mismatch.** That is the design working, and it is silent from the player's
side: every station is absent.

**Check:** the redscript log for `roster patched to N stations`. If it reads
`slot N is empty - too early to patch, abandoned` or does not appear, the patterns have moved.

The detour has one more thing to move: the stub calls the two dial-order switches by the targets it
reads from the block it replaces, so a patch that changes what those functions take or return breaks
next-station in a car with every byte check still passing. **Check:** in a car, press next from the
last vanilla station and again from the last custom one. The first must reach the first custom
station and the second must wrap to the first vanilla one on the dial.

## 2. The routing bank's cited objects

`red4ext/plugins/NativeRadioFramework/nrf_routing.bnk` is built by `tools/make_routing_bank.py` from
the game's own banks. It **copies** the two Broadcast Sends, so those cannot be moved out from under
it, but it still cites three objects in `mod.bnk` by id and clones three more:

| id | what | from |
| --- | --- | --- |
| `2845221403` | the `mod_sfx_radio` Event, the clone template | `mod.bnk` |
| `784902175` | its Play action | `mod.bnk` |
| `529198484` | its CAkSound | `mod.bnk` |
| `758059012` | Wwise Time Stretch, cited by the clone | `mod.bnk` |
| `453120594` | the parent ActorMixer, cited by the clone | `mod.bnk` |
| `818835100` | the Wwise Audio Input source | `mod.bnk` |

**A cited id that no longer exists does not error.** The effect is absent, the sound leaves the
broadcast chain, and it plays its dry output about 15 dB hot at every distance while every
script-side check still passes.

**Check:** rebuild the bank. The script asserts on every id it needs, so a moved object is a build
failure rather than a silent one:

```
python tools/make_routing_bank.py <mod.bnk> <radio.bnk> red4ext/plugins/NativeRadioFramework/nrf_routing.bnk
```

## 3. The send trims, if the dial has been retuned

The bank carries **copies** of Radio Vexelstrom's two sends, -2.0 dB stereo and -5.0 dB mono. A copy
cannot be broken by a patch, and it also does not follow one: if CDPR retunes the radio dial, vanilla
stations move and custom stations do not.

**Check:** re-derive the table and compare. Dump `radio.bnk` with wwiser, take every
`CAkMusicRanSeqCntr` as a station, read its two `NodeInitialFxParams` ids, resolve each to a
`CAkFxCustom` or `CAkFxShareSet`, and take the graph point at `From = 0.0` on its RTPC for
`1631578750`. wwiser stores a dB-scaled point as `10^(dB/20) - 1`, so the dB is `20*log10(To + 1)`.
`fxID 0x000529A3` is the stereo send, `0x000329A3` the mono one.

If Vexelstrom's numbers have changed, edit `STATION_STEREO` / `STATION_MONO` in the build script or
its trim constants, and rebuild.

## 4. AudioXL

The framework depends on AudioXL for every sound, and on three of its natives in particular:
`RegisterSoundEx`, `SetGain` and `LoadBank`.

- **`LoadBank` returns 1 both for a load and for a bank queued** because the engine's audio system is
  not up yet. A 1 at boot is a promise, not a fact; only a later failure is reported.
- AudioXL resolves its own addresses per game build. If it reports its native as unavailable, every
  station is silent and the framework's own log says nothing is wrong.

**Check:** AudioXL's log for `native: ready (game <version>, ...)`.

## 5. The resources written as they load

Membership, the station entry, the event rows and the localization entries are all written into
resources while they load: `cooked_metadata.audio_metadata`, `eventsmetadata.json` and
`onscreens.json`. A patch that changes any of those class shapes breaks the writes.

**Two invariants worth re-reading if a station goes quiet or nameless:**

- The localization list is **sorted by `primaryKey` and searched with a binary search**, so a row
  appended to the end is unreachable whatever its key.
- **The custom-sound TYPE needs its own event-table row**, not just the tracks. Without it the bank
  loads, every track registers, every station is built, every log line reads as success, and there is
  silence.

## 6. The schedule margin

A track's event row is written at `duration - 0.5 s`. The engine re-posts a slot's track when the
voice ends while that slot is still current, so a declared duration at or above the decoded length
makes a track play twice. The margin is bounded on the other side by the free-running station clock,
which a short slot advances slightly faster than one slot per post.

**Check:** if tracks start doubling, or a track is skipped every few dozen plays, `NRFScheduleMargin`
is the number to move.

## 7. The vanilla frequencies

The dial order is by frequency, and the game stores no frequency: it is the number at the front of
each display name. The plugin carries the fourteen vanilla ones in `kVanillaFrequency`
(`plugin/src/Main.cpp`) to decide where a custom station is inserted. The fourteen's own order is
asked of the game's switch at patch time, so it cannot drift; only a custom station's place can.

**Check:** the redscript log line `dial order ...` lists `ERadioStationList` values in dial order.
The fourteen must read `4 0 11 10 1 9 8 6 13 2 3 7 5 12` with the custom stations (14 and up)
between the right neighbours. If CDPR retunes a station, its number in `kVanillaFrequency` moves
with it; the station names are `docs/compiled-station-roster.md`'s frequency table.

## After any of the above

Run the whole in-game set rather than only the thing that changed. In order, stopping at the first
failure:

1. a station plays on the Radioport, in a vehicle and at a world device
2. switching station in a vehicle stops the previous track, and a vehicle takes over from the
   Radioport
3. walking away from a world device attenuates - level holding with distance means the sound is off
   the broadcast chain whatever it sounds like up close
4. a wanted star ducks the audio and combat stops it
5. the Music slider moves it
6. loading a second save without restarting keeps a station playing
7. a level capture at a world device: 0 one-sample moves of more than half scale, and the station
   inside the vanilla loudness spread
