# Labels are localization keys

Every label the game shows for a station is a key that is resolved at the UI, never text. The
engine's name table holds one per station, `audioRadioTrack` holds one per track, and the script
providers return one per channel. Writing text where the game expects a key is what makes a label
vanish and the vehicle popup's selection match nothing.

## Where the keys are

| Place | Holds | Resolved by |
| --- | --- | --- |
| the compiled name table, slot per station | `Gameplay-Devices-Radio-RadioStation*` | the native `GetRadioReceiverStationName` returns it as a `CName`; the dashboard does `SetText(NameToString(name))` and the widget resolves the string, the popup calls `GetLocalizedTextByKey` |
| `audioRadioTrack.localizationKey` / `primaryLocKey` | the track title key, and its numeric hash | the popup and dashboard, by the numeric key |
| `RadioStationDataProvider.GetChannelName` (script) | the same station key, as a `String` | device UI, `GetLocalizedText` |
| `RadioStation.<x>.displayName` (TweakDB) | `LocKey#<n>` | the radio wheel, `GetLocalizedText` |

`[M]` The vehicle popup compares `GetLocalizedText(record.DisplayName())` with
`GetLocalizedTextByKey(receiverStationName)` to mark the playing station. Both sides must resolve to
the same text.

The framework mints one key per station (`Gameplay-Devices-Radio-NRF-<name>`) and one per title
(`Gameplay-Devices-Radio_tracks-NRF-<name>-NN`), puts the station key in the name table and the
title key in the track row, and registers the text against them. A manifest never sees a key.

## A key resolves by string only inside the game's three namespaces

`[M]` `Cyberpunk2077.exe` 2.31. `LoadTexts` (RED4ext hash `3550098299`, RVA `0x261018`) only loads the
resource and returns its root. Its single caller, at `0x58dd6c`, then walks every entry of the loaded
list (0x68 bytes each) and calls a register-entry function at `0x58ddf0`, which fills two maps on the
localization manager:

| Map | Keyed by | Filled from |
| --- | --- | --- |
| `+0x38` | `primaryKey` | every entry |
| `+0x40` | FNV1a64 of the `secondaryKey` text | every entry with a secondary key |

**Before hashing, a secondary key that starts with `ui-`, `gameplay-` or `common-` (compared
case-insensitively, the literals at `0x2af2fc4`) is UPPERCASED (`0x58e2e8`, an ASCII `a-z` loop),
and a key outside those namespaces is hashed as written.** The string-side lookup (`GetLocalizedText`,
`inkText.SetText`, `SetLocalizedTextString`) uppercases what it is asked for, so a key outside the
three namespaces never matches, while `GetLocalizedTextByKey(CName)` goes by the CName hash and does
not care. That is the whole reason a title (looked up by hash) resolved while a station name (looked
up by string) echoed its key, and why an ArchiveXL key beginning `Gameplay-` resolved from the console
when `NRF-Station-...` did not.

Because the walk runs after `LoadTexts` returns, rows added by an after-hook (ArchiveXL, Codeware) and
rows inserted while the resource loads are all indexed. The namespace is the only gate.

## Two rows per string

`localizationPersistenceOnScreenEntries.entries` in `base\localization\<lang>\onscreens\onscreens.json`
is ordered by `primaryKey` on disk, and ArchiveXL's merge keeps it that way with a `lower_bound`.
`[M]` The engine does not depend on the order: the register walk above visits every row wherever it
sits. An earlier reading that an appended row is unreachable came from the namespace gate, not from
the position.

A string is registered as two rows, which is what ArchiveXL does:

| Row | `primaryKey` | `secondaryKey` |
| --- | --- | --- |
| 32-bit | `FNV1a32(key)` | the key text |
| 64-bit | `FNV1a64(key)` | empty |

**A `primaryKey` of 0 is indexed by nothing**; ArchiveXL fills it from the secondary key, and a mod
writing rows itself must too.

`audioRadioTrack.primaryLocKey` is a `Uint64`. Vanilla rows carry small numeric keys; ArchiveXL's
pattern is the 64-bit hash. The framework writes the 32-bit hash there, which resolves because the
32-bit row exists. A divergence from vanilla, not a fault.

**Appending is correct for the other two resources.** `eventsmetadata`'s event array and
`cooked_metadata`'s entry list are scanned linearly. Patching a resource at load is not one
technique: ask how the game finds a row in that list before choosing where to put yours.

## What a failed lookup looks like

`[M]` Two different failure shapes, and they mislead in different directions:

- **A widget handed a key that resolves to nothing keeps its previous text.** It does not blank. So a
  world device shows the *previous* station's name, which reads as a refresh-order bug.
- **`inkText.SetText` and `GetLocalizedText` hand back the string they were given when it is not a
  key they know.** So the in-car stereo prints the key.
- **`GetLocalizedTextByKey(CName)` returns an empty string for a CName it cannot resolve**, including
  a `LocKey#<n>` form, which it does not parse.

## Why nothing is wrapped for a label

Five UI wrappers were written to substitute a station's name at the widget, and deleted once the
name table was found. A wrong label means a table that was not extended, and the rule generalises:
look for another 14-slot array before writing a script wrapper to correct the output. The only
wrappers left are on `RadioStationDataProvider` and `VehiclesManagerDataHelper`, which are game
redscript holding the fourteen as literals with nothing behind them.
