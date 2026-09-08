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
[#3](https://github.com/spuddeh/cp2077-native-radio-framework/issues/3)):

| sound | stereo send (world devices) | mono send (Radioport) |
| --- | --- | --- |
| `mod_sfx_radio` | **+2.9 dB** | -2.0 dB |
| hottest vanilla station | +0.9 dB | -5.0 dB |
| Growl FM | -4.0 dB | -5.0 dB |
| quietest vanilla station | -4.0 dB | -7.0 dB |

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

**Two ways to meet vanilla.** A per-row gain applied in the samples (AudioXL has `SetGain`;
nothing calls it at registration) with a default near 0.45, which lands the stereo send at Growl FM's
trim and leaves the mono send 3.9 dB under it. Or two curve points changed in `mod.bnk`, shipped as
an archive, which is exact on both receivers and corrects every REDmod custom station too, at the
price of being a vanilla-file replacement.

### The `axl_*` types are not an alternative

`[M]` AudioXL's own routing bank defines `axl_voice_2d`, `axl_music_2d`, `axl_radio_2d`, `axl_sfx_2d`
and `axl_master_2d`. Each is a 2D sound on a mixer bus, tied to no game object and to no
`radio_station` switch. On `axl_radio_2d` the Radioport and a car played at once, a car could not
take over, and a world device sounded like it worked because the audio was audible everywhere. A
station on those is a parallel player, not a station.

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
4. **It never seeks.** `AudioFeed::Start` sets the voice position to the row's `start` (default 0).
   The engine keeps a per-slot position field; AudioXL writes it every buffer and never reads it.
5. **MP3, OGG and FLAC are decoded in full at registration.** `stream` applies to WAV only, which is
   memory-mapped. Eleven album tracks are about 750 MB of resident PCM.
6. **Banks load from memory** through the engine's `LoadBankMemoryCopy`.

## The symptoms, mapped

| Heard | Cause | Mark |
| --- | --- | --- |
| Right song after tuning back, from 0:00 | the engine picked the track from its clock; the renderer starts at 0, and the engine hands no offset | `[M]` both sides ([#1](https://github.com/spuddeh/cp2077-native-radio-framework/issues/1)) |
| Each track plays twice on a world device | declared duration longer than the decoded length by the LAME gapless trim; the engine re-posts the slot | `[M]` cause; fix awaiting a run ([#15](https://github.com/spuddeh/cp2077-native-radio-framework/issues/15)) |
| World devices quieter; car and Radioport fine | `818835100`'s attenuation, tuned for a broadcast SFX, not music. `RegisterSoundEx`'s `distance` is the untested knob | `[I]` ([#2](https://github.com/spuddeh/cp2077-native-radio-framework/issues/2)) |
| Static and crackle, at devices only | `mod_sfx_radio`'s stereo send is trimmed +2.9 dB, 3 to 7 dB above every vanilla station; a source clamped at 0 dBFS wraps in the next 16-bit stage | `[M]` ([#3](https://github.com/spuddeh/cp2077-native-radio-framework/issues/3)) |
| Hundreds of MB of RAM | decode at registration | `[M]` ([#4](https://github.com/spuddeh/cp2077-native-radio-framework/issues/4)) |

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
instant. **So the declared duration must equal the decoded length.** Declare longer and the voice ends
inside its own slot, the slot is still current, and the engine posts the same track again from 0:00.
The Tool FM MP3s carry a LAME gapless tag (delay 576, padding 717 to 1681 frames); dr_mp3 trims it,
and a duration counted from the raw frame count is 27 to 47 ms too long. `Duration.hpp` subtracts the
trim with dr_mp3's own arithmetic. Declare shorter and the voice outlives its slot; what the engine
does then is unmeasured.

## Events, and why the row alone is not enough

`[M]` `GameInstance.GetAudioSystem().Play(name)` resolves a `CName` through `eventsmetadata.json`. An
event with no row there cannot be posted by name and fails silently. The framework writes one row
per track as that resource loads: `redId` the event name, `wwiseId` from AudioXL (FNV-1 32-bit of the
lowercased name), `minDuration` and `maxDuration` the track's length. A registry row alone plays from
a receiver, but the station schedules against the event row, so both exist.
