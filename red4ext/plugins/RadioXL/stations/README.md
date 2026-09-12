# Station manifests

A station is one folder in here, named after the mod that ships it:

```text
red4ext/plugins/RadioXL/stations/<YourMod>/station.json
```

Nothing in this folder is shared, so any number of station mods install side by side.

**A station mod is a manifest, its audio files, and at most an icon archive.** No yaml, no
soundbank, no redscript. Everything else is built from the manifest at load.

## station.json

```json
{
  "name": "radio_station_20_yourstation",
  "displayName": "104.9 Your Station",
  "speaker": "Ash",
  "tracks": [
    { "file": "audio/first.mp3",  "title": "Artist - First Song" },
    { "file": "audio/second.flac", "title": "Artist - Second Song" }
  ]
}
```

| Field | What it is |
| --- | --- |
| `name` | The station's own CName: letters, digits and underscores only. It must be unique across every installed station mod. |
| `displayName` | The label the game shows. Put the frequency at the front. |
| `speaker` | Optional. The station's DJ. Defaults to `None`. |
| `gain` | Optional. A level trim on every track, `0` to `1`. Defaults to `0.56`, which is -5 dB. |
| `shuffle` | Optional. `true` plays the tracks in a new random order each time the game starts. Defaults to `false`: the order they are written in. |
| `icon` | Optional. An inkatlas part name. Defaults to the RadioXL glyph. |
| `atlas` | Optional. The inkatlas holding that part, as a depot path (`mymod\gui\icons.inkatlas`, no `base\`). Required when `icon` is set. |
| `tracks[].file` | An audio file, relative to this manifest's folder. |
| `tracks[].title` | Optional. The song title, shown as written. |

`speaker` names one of `Stanley`, `MaximumMike`, `Ash`, `Kurtz` or `PoliceDispatch`. Every vanilla
station names one; a station without one plays.

`gain` is the station's mastering trim, the same knob every vanilla station carries. The game feeds
a custom station to world devices hotter than its own stations, so a track mastered to 0 dBFS
crackles there at `1`. The default sits inside the vanilla range; raise it only for quiet material.

**The frequency lives at the front of `displayName`**, because the game has no field for it. The
number decides where the station sits on the dial: in the vehicle list, and in the order every
receiver steps through when you press next. A station whose display name does not start with a
number goes after every station that has one.

## When the manifest is wrong

**The file must be JSON.** No comments, no trailing commas, double quotes only, and a backslash in a
path written twice (`"mymod\\gui\\icons.inkatlas"`), or once as a forward slash.

**Every fault is logged with the file and the line, and the station is skipped whole.** A missing
`name`, a `tracks` that is not an array, a `speaker` the game does not have, a `gain` written as a
string, an `icon` with no `atlas` - each names its line in the RED4ext log:

```text
[RadioXL] YourMod/station.json:7: "speaker" must be one of None, Stanley, MaximumMike, Ash, Kurtz, PoliceDispatch: "Stanly"
[RadioXL] YourMod/station.json: skipped
```

A key the framework does not know is logged the same way and ignored, so a typo in `displayName`
shows up rather than quietly leaving the station nameless.

## What the manifest does NOT carry

**No durations.** The framework reads each file's length from its headers at load, and the station
schedules the next track against that. A hand-written duration is a second place for it to be wrong.
A file whose length cannot be read is dropped, and the log names it.

**No event names.** They are derived as `<name>_01`, `<name>_02` and so on, so a filename with a
space or an accent in it never reaches an event name.

**No Wwise ids, no `index`, no TweakDB records.** A station's record index is its position on the
dial, which depends on which other station mods are installed and their frequencies - so no mod can
know its own in advance. The framework creates the records.

## The icon

Import the texture the way the game's own station atlas is built, or it renders wrong:
`TEXG_Generic_UI`, `TRF_TrueColor`, `TCM_QualityColor`, no mip chain, not streamable, **alpha
premultiplied** and **vertically flipped on import**. The game's UI textures store black under every
transparent pixel; a PNG with white there shows as a white box, and an unflipped import shows upside
down. In WolvenKit both are import switches. The atlas part's UV rect selects the used region, so the
sheet can be padded to a multiple of 4.

## The audio

Put the files beside the manifest. **AudioXL is what loads them**, so it is a hard requirement for
any station with files: WAV, MP3, OGG or FLAC. This framework does not decode, stream or mix
anything.

A track whose file AudioXL will not take is dropped, and the log names it. A station with no
playable tracks is skipped rather than registered empty.

## Song titles and the station name

Both are plain text here, and both are registered as real localization entries at load. **Every
label the game shows is a key, not text** - the engine's station name table holds one, and so does
every radio track row - so the framework mints a key and registers the text against it. That is why
a custom station's name and titles resolve everywhere a vanilla one's do.

## Two things that will bite

**A station name that another installed mod already uses is skipped**, and the log says which mod
won. Prefix yours.

**A track whose file is missing plays nothing** and the station is shorter than the manifest says.
The log names every file AudioXL refused.
