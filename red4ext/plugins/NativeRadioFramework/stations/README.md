# Station manifests

Every station is one folder in here, named after the mod that ships it:

```
red4ext/plugins/NativeRadioFramework/stations/<YourMod>/station.json
```

Nothing in this folder is shared, so any number of station mods install side by side.

## station.json

```json
{
  "name": "radio_station_20_hangouts",
  "displayName": "Hangouts FM",
  "icon": "",
  "tracks": [
    { "event": "mus_radio_20_hangouts_01", "duration": 187.474 },
    { "event": "mus_radio_20_hangouts_02", "duration": 165.818 }
  ]
}
```

| Field | What it is |
| --- | --- |
| `name` | The station's own CName. It must be unique across every installed station mod. |
| `displayName` | Shown on the radio dial. |
| `icon` | The station's dial icon. |
| `tracks[].event` | A Wwise event name, posted to play the track. |
| `tracks[].duration` | The track's audible length in **seconds**. |

**`duration` is not decoration.** The station schedules the next track against it, so a value that
is too short cuts the song off and one that is too long leaves dead air.

## The TweakDB record

`record` names a `gamedataRadioStation_Record` your mod ships through TweakXL, carrying the
station's `displayName`, `icon` and `index`. The display name is where the frequency lives - the
game has no separate field for it.

**Do not try to pick your own `index`.** The value in your yaml is overwritten at load. A station's
index has to equal the roster slot the framework gave it, which depends on how many station mods
are installed and in what order they were found - so no mod can know its own index in advance. The
popup plays whatever `Index()` returns, so a wrong one plays the wrong station.

Put any valid number in the yaml to satisfy the record type. `14` is as good as any.

## The audio

This framework does not load, decode or stream sound. A track's event has to exist in a soundbank
that something else loads, which in practice means **AudioXL**.

A station whose tracks are all vanilla radio events needs no bank at all.

## Two things that will bite

**A station name that another installed mod already uses is skipped**, and the log says which mod
won. Prefix yours.

**A track whose event is missing from the loaded banks plays silence** and reports no error. If a
station is quiet, check the bank loaded before suspecting the manifest.
