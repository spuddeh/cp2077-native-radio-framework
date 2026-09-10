# The audio path

The station side is the engine's. The sound is the one place a custom station is not on vanilla's
path, and that one difference explains most of what still sounds wrong.

## What a vanilla track is

`[M]` A Wwise `MusicSegment` with one `MusicTrack`, streamed from a `.wem` in the archives, parented
to the station's `MusicPlaylist` container in `radio.bnk` or `cp_music.bnk`. The segment inherits the
station's mix. The engine starts it at an offset computed from the station clock, which is how a
vanilla station resumes mid-song when a receiver tunes back in.

Producing that shape for new audio needs a `.wem` (Wwise Vorbis, which only Wwise 2023.1 encodes;
Wwise's built-in PCM codec is an unmeasured alternative), a generated bank (proven for single tracks
by <https://github.com/spuddeh/cp2077-hardest-to-be-growl-fm>; a multi-track probe bank played only
its first event), and an archive to carry the media, because streamed `.wem` files are fetched from
the archive depot and a loose file is never found.

## What the framework uses instead: `mod_sfx_radio`

`[M]` The engine has a **custom-sound registry**, the path REDmod's `customSounds` writes into, 4096
rows. A row is a name, a type, PCM data and a format. Posting the row's name plays the **type's**
event with the row's PCM fed through a Wwise Audio Input source. AudioXL fills that registry.

`mod_sfx_radio` is one of the game's own types, in the game's `mod` bank. SoundDB: its PLAY target
is sound object `818835100`, generator `AUDIO_INPUT`, with an RTPC on `volume_music`. REDmod
documents the type as "needs to be tuned to a broadcast channel". **It is CDPR's type for custom
audio that a radio receiver plays**, and it follows the Music slider, not SFX.

`[M]` On it, the radio system owns the sound: a car takes the station over from the Radioport, a
world device plays or stays silent by its own state, switching stations stops the previous track.

### What the `mod_sfx_radio` object is, decoded from the banks

`[M]` `mod.bnk`, `radio.bnk` and `init.bnk` parsed with wwiser:

| | `mod_sfx_radio` (custom row) | a vanilla station playlist |
| --- | --- | --- |
| object | `CAkSound 529198484`, source Wwise Audio Input | `CAkMusicRanSeqCntr` (`375417660` Growl FM, `440066888`, ...) |
| insert effects | **Wwise Time Stretch** `758059012`, CPR Voice Broadcast Send `772871769` (mono), CPR Voice Broadcast Send `385769109` (stereo) | its own pair of Broadcast Send sharesets, one mono and one stereo (26 pairs in `radio.bnk`, one per playlist) |
| positioning | 3D, attenuation enabled, no attenuation object of its own | same bits |
| bus | `918052088` -> `1151059771` (Parametric EQ) -> `2996874604` -> `1836253337` -> Master | `666212655` (Parametric EQ) -> `music` -> Master |
| sliders | RTPC `volume_music` on the sound | the music bus |
| base props | Volume -96 dB, GameAuxSendVolume -96 dB | none |

### The vanilla rule: the dry path is muted and the send is the station

`[M]` **Every one of the 26 station playlists in `radio.bnk` carries `Volume -96 dB` on its own dry
output and two CPR Voice Broadcast Send inserts, without exception.** A station is not a sound that
also feeds a send - the send is the only way it is heard at all. So the send trim is not a
correction on top of a level, it *is* the station's level, and matching a station means matching a
send trim.

Both dials are narrow: the whole roster spans 4.9 dB on the stereo send and 2 dB on the mono one.

To read the table back after a game patch: dump `radio.bnk` with wwiser, take every
`CAkMusicRanSeqCntr` as a station, read its `OverrideBusId` and its two `NodeInitialFxParams` ids,
resolve each id to a `CAkFxCustom` **or** a `CAkFxShareSet` in the same bank, and take the graph
point at `From = 0.0` on its RTPC for `1631578750`. `fxID 0x000529A3` is the stereo send and
`0x000329A3` the mono one.

`[M]` The consequence for anything that adds a track by cloning bank objects, measured on
<https://github.com/spuddeh/cp2077-hardest-to-be-growl-fm>: **a segment does not inherit that routing
from a parent playlist in another bank.** It plays dry, at the source file's own level, about 15 dB
hot, holding level with distance until the emitter's range cuts it at 45 to 50 m. Turning the device
off still stops it, so the station is scheduling it correctly and only the audio is off the chain,
and every script-side check passes. The node has to carry the station's two send effects, its bus
and its -96 dB Volume itself.

The **CPR Voice Broadcast Send** is CDPR's own plugin and the mechanism behind "tuned to a
broadcast channel". Every station has its **own pair** of send sharesets, and so does `mod_sfx_radio`.
The mono send (`207267`) takes the RTPC `radio_broadcast_channel` (default 8) and feeds the Radioport;
the stereo send (`338339`) takes `radio_broadcast_channel_left` and `_right` (defaults 58) and feeds
the world-device receive sounds. Both carry a curve on `radio_broadcast_mute` (`1631578750`, default
0 = unmuted, 1 = -96 dB), and **the curve's value at 0 is a per-station level trim**. wwiser stores a
dB-scaled curve point as `10^(dB/20) - 1`; decoded that way every vanilla trim is a whole or half dB.
The four attenuations in `mod.bnk` belong to the occlusion, room, street and city sounds, not to
this one.

`[M]` **The trims are the difference, and they are the crackle** (issue
[#3](https://github.com/spuddeh/cp2077-radio-xl/issues/3)):

| sound | stereo send (world devices) | mono send (Radioport) |
| --- | --- | --- |
| `mod_sfx_radio` | **+2.9 dB** | -2.0 dB |
| hottest vanilla station | +0.9 dB | -5.0 dB |
| Growl FM | -4.0 dB | -5.0 dB |
| quietest vanilla station | -4.0 dB | -7.0 dB |

Every trim in the roster is a whole or a half dB. Two stations sit on a different bus, and two share
one mono send rather than owning a pair, so reading only the `CAkFxCustom` objects and not the
`CAkFxShareSet` ones misses part of the table.

dr_mp3 decodes to int16 and clamps, so a modern master reaches the send already on 0 dBFS. The
stereo send adds 2.9 dB and the next 16-bit stage wraps: the recorded artefact is a bass peak whose
samples flip sign in runs of one to three while keeping their magnitude, 6,250 half-scale jumps in
160 s of *Afterlife* on Tool FM against 4 in the same song on Growl FM at the same device, and 95 %
of them where the source peaks above -2.1 dBFS. The Radioport sits on the mono send at -2 dB, so a
clamped source stays under the rail there.

The **Time Stretch** is the other structural difference and it is not the crackle: its RTPC
(`1400903616`, name unresolved, default 1) maps 0 to 200 % and 1 or more to 100 %, `[M]` Wwise 2023.1
Help says 100 % is no stretch, and the artefact has no grain period. `[I]` It exists so a custom
sound slows with the world when a bus-level pitch shift cannot reach an Audio Input source.

**A sample gain cannot meet vanilla on both receivers, so the framework does not use one.** The
stereo path needs -4.95 dB and the mono path -3.0; one figure applied to the audio lands devices
mid-dial and leaves the Radioport at the bottom of the vanilla range. Editing two curve points in
`mod.bnk` is exact on both, at the price of replacing a vanilla file and moving every REDmod custom
station with it.

`[M]` **The framework takes a third route: its own custom-sound type, in its own bank.** A type is
whatever a loaded bank defines, and `radioxl_routing.bnk` clones `mod_sfx_radio`'s Event, Play action and
CAkSound, citing its own copies of a vanilla station's two Broadcast Sends instead of that object's.
The level then comes from the same mechanism every vanilla station uses, on both receivers, and no
game file is replaced. Measured after the change: **0 wrap artefacts in 550 s** where the same
passage gave 6,250 in 160 s, true peak -1.4 dBFS, and a custom station inside the vanilla spread
rather than above it.

The sends are **copied rather than cited**, because a cited id that a patch or another mod moves does
not error - the effect is absent, the sound leaves the broadcast chain, and it plays dry about
15 dB hot at every distance while every script-side check still passes. The cost is that a retuned
vanilla dial no longer moves this one: re-derive the trims after a game patch and rebuild.

### A receiver decides what it hears; the source only broadcasts

`[M]` **A world device does not stop the station's voice when it is switched off or retuned. It stops
listening.** `radio.swift`, `speaker.swift`, `jukebox.swift` and `lift.swift` all do the same two
things: set the device's own `radio_station` switch, and start or break-loop its `radio_idle` effect.
Nothing there reaches the voice. That is why a vanilla station is mid-song when a receiver tunes back
in, and why a car taking the station over from the Radioport is arbitration between receivers rather
than a handover of one sound.

So what a bank object decides is not whether the radio system controls it. It is whether the sound is
on the broadcast chain at all.

### The `axl_*` types are not an alternative

`[M]` AudioXL's own routing bank defines `axl_voice_2d`, `axl_music_2d`, `axl_radio_2d`, `axl_sfx_2d`,
`axl_master_2d` and `axl_radioport_2d`. On `axl_radio_2d` the Radioport and a car play at once, a car
cannot take over, and a world device sounds like it works because the audio is audible everywhere. A
station on those is a parallel player, not a station.

`[M]` **The cause is the missing chain, not positioning.** Five of the six carry
`uBitsPositioning 3` and `uBits3d 8`, the same bits `mod_sfx_radio` carries; only `axl_radioport_2d`
is 2D. Against `mod_sfx_radio`, `axl_radio_2d` (`4061179639`) differs in exactly two ways that
matter: it carries **no effects at all**, so neither Broadcast Send, and **no `Volume` property**, so
its dry output is not muted. It is heard directly on its own bus, which no receiver arbitrates.

The consequence for anything built on this path: **a custom sound keeps the receivers' behaviour for
as long as it keeps the two sends and the -96 dB dry mute.** Changing which send objects it cites
changes its level and nothing else.

## What AudioXL's renderer does, and does not do

From its source, all `[M]`:

1. **It fills the engine's registry** through the engine's own register function, after
   `EnsureEnabled` - which needs the engine's audio system pointer, null until the `AudioInit` hook
   fires. Registrations before that are queued.
2. **It replaces the engine's renderer.** `EnsureEnabled` calls the engine's `SetCallbacks` with
   AudioXL's `Execute` and `Format`. Every registry row, REDmod's included, is then rendered by
   AudioXL's code.
3. **The render is a copy.** 16-bit frames memcpy'd into Wwise's buffer at the file's own sample
   rate. Bit-exact at gain 1. Wwise resamples.
4. **It seeks only where told.** `AudioFeed::Start` sets the voice position to the row's `start`
   (default 0). The engine keeps a per-slot position field; AudioXL writes it every buffer and never
   reads it. From AudioXL 0.3.0 `PlayFrom(name, seconds)` sets a one-shot start for the next voice
   on a row and `Position(name)` reads the playing voice's position; that pair is how the framework
   resumes (`Clock.reds`).
5. **A compressed track of 45 s or more streams from disk** from AudioXL 0.3.0; shorter ones, and any
   row with a loop, a start/end region or a rate, are decoded in full at registration. `stream: true`
   forces streaming. Before 0.3.0 every MP3, OGG and FLAC was resident PCM, eleven album tracks about
   750 MB.
6. **Banks load from memory** through the engine's `LoadBankMemoryCopy`.

## The symptoms, mapped

| Heard | Cause | Mark |
| --- | --- | --- |
| Right song after tuning back, from 0:00 | the engine picked the track from its clock; the renderer starts at 0, and the engine hands no offset | `[M]` both sides; the framework now hands AudioXL the offset itself ([#1](https://github.com/spuddeh/cp2077-radio-xl/issues/1)) |
| Each track plays twice on a world device | declared duration longer than the decoded length by the LAME gapless trim; the engine re-posts the slot | `[M]` cause; fix awaiting a run ([#15](https://github.com/spuddeh/cp2077-radio-xl/issues/15)) |
| World devices quieter; car and Radioport fine | `818835100`'s attenuation, tuned for a broadcast SFX, not music. `RegisterSoundEx`'s `distance` is the untested knob | `[I]` ([#2](https://github.com/spuddeh/cp2077-radio-xl/issues/2)) |
| Static and crackle, at devices only | `mod_sfx_radio`'s stereo send is trimmed +2.9 dB, 3 to 7 dB above every vanilla station; a source clamped at 0 dBFS wraps in the next 16-bit stage | `[M]` fixed by the framework's own type ([#3](https://github.com/spuddeh/cp2077-radio-xl/issues/3), [#17](https://github.com/spuddeh/cp2077-radio-xl/issues/17)) |
| Hundreds of MB of RAM | decode at registration, before AudioXL 0.3.0 streamed long tracks | `[M]` ([#4](https://github.com/spuddeh/cp2077-radio-xl/issues/4)) |

## The engine never hands a start offset on this path

`[M]` A probe build of AudioXL (`tools/audioxl-feed-probe.patch`) logs the engine's per-slot position
at `AudioFeed::Start`, before the first render overwrites it. Seven voice starts, a mid-song tune-in
among them: 0 every time. The engine writes 0 into the slot when it posts. So no renderer can resume
by reading that field. Resume means either the framework computing the offset from its durations and
the station clock and handing it to AudioXL as a per-row start, or the vanilla shape above, with its
three unmeasured steps.

## The engine posts the next track when the voice ends, and it posts the slot its clock names

`[M]` Same probe: the next voice starts about 30 ms after the previous one retires at its last frame,
never on a clock boundary. Which track it posts is whatever slot the station clock is in at that
instant. Declare longer and the voice ends inside its own slot, the slot is still current, and the
engine posts the same track again from 0:00.

`[M]` **So the declared duration must sit BELOW the decoded length, and an exact one does not.** A
duration at or above the real length loses that race about half the time, because the event row
holds a 32-bit float whose step is 15 microseconds at three minutes and the rounding decides the
sign. Two Tool FM tracks four microseconds either side of their own length, from the file lengths
and one boundary-to-boundary observation:

| track | decoded | declared | difference | heard |
| --- | --- | --- | --- | --- |
| Lost Keys | 226.324917 | 226.324921 | +4 us | plays twice, slot held 453.19 s |
| Afterlife | 169.721333 | 169.721329 | -4 us | plays once |

The repeat is a full second play-through, not a fragment, so a slot reads as exactly twice its
track. It is invisible as a slot boundary, because a re-posted slot reports the same track.

`[M]` **Vanilla does not run that race**: `mus_radio_12_afterlife` declares
`minDuration = maxDuration = 166` for 169.72 s of audio, and every vanilla radio row carries seconds
of margin. A station that under-declares has its slot end first, and the engine waits for the voice.

So subtracting the LAME gapless tag (delay 576, padding 717 to 1681 frames, which dr_mp3 trims and
which leaves a raw frame count 27 to 47 ms long) is necessary but not sufficient: accuracy is the
wrong target, and the row is written at `duration - 0.1 s` to stay clear of the float step.

## Events, and why the row alone is not enough

`[M]` `GameInstance.GetAudioSystem().Play(name)` resolves a `CName` through `eventsmetadata.json`. An
event with no row there cannot be posted by name and fails silently. The framework writes one row
per track as that resource loads: `redId` the event name, `wwiseId` from AudioXL (FNV-1 32-bit of the
lowercased name), `minDuration` and `maxDuration` the track's length. A registry row alone plays from
a receiver, but the station schedules against the event row, so both exist.

`[M]` **The custom-sound TYPE needs a row of its own, on the same rule.** AudioXL stores a row's type
as the CName hash of the type string, and the engine resolves that name through this table to reach
the Wwise event. A type absent from it plays nothing and reports nothing: the bank loads, every track
registers, every station is built, every log line reads as success, and there is silence. AudioXL
registers its own six `axl_*` types here too.

`[M]` **A bank load returning 1 does not mean the bank is live.** AudioXL returns 1 both for a load
and for a bank queued because the engine's audio system is not up yet, which is the usual case at
boot. Only a later failure is reported, so 1 at registration time is a promise rather than a fact.
