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
| Right song after tuning back, from 0:00 | the engine picked the track from its clock; the renderer starts at 0 | `[M]` renderer side. **Open:** whether the engine asks for an offset on this path at all ([#1](https://github.com/spuddeh/cp2077-native-radio-framework/issues/1)) |
| World devices quieter; car and Radioport fine | `818835100`'s attenuation, tuned for a broadcast SFX, not music. `RegisterSoundEx`'s `distance` is the untested knob | `[I]` ([#2](https://github.com/spuddeh/cp2077-native-radio-framework/issues/2)) |
| Static and crackle, worst at devices | the object's effect chain, or feed underruns | `[I]` ([#3](https://github.com/spuddeh/cp2077-native-radio-framework/issues/3)) |
| Hundreds of MB of RAM | decode at registration | `[M]` ([#4](https://github.com/spuddeh/cp2077-native-radio-framework/issues/4)) |

## The one question that decides the direction

**Does the engine request a start offset for a custom-sound row?** A local AudioXL build logging the
engine's slot position at `Start`, before AudioXL overwrites it, answers it in one run.

- **Yes:** resume is a five-line change in AudioXL - read the field at voice start. Stay on
  `mod_sfx_radio`, fix decode-on-the-fly upstream, tune attenuation.
- **No:** no renderer can resume on this path. Either the framework computes the offset itself from
  its durations and the game clock and hands it to AudioXL through a new per-row `SetStart`, or the
  audio moves to the vanilla shape above, with its three unmeasured steps.

## Events, and why the row alone is not enough

`[M]` `GameInstance.GetAudioSystem().Play(name)` resolves a `CName` through `eventsmetadata.json`. An
event with no row there cannot be posted by name and fails silently. The framework writes one row
per track as that resource loads: `redId` the event name, `wwiseId` from AudioXL (FNV-1 32-bit of the
lowercased name), `minDuration` and `maxDuration` the track's length. A registry row alone plays from
a receiver, but the station schedules against the event row, so both exist.
