# Labels are localization keys

Every label the game shows for a station is a key that is resolved at the UI, never text. The
engine's name table holds one per station, `audioRadioTrack` holds one per track, and the script
providers return one per channel. Writing text where the game expects a key is what makes a label
vanish and the vehicle popup's selection match nothing.

## Where the keys are

| Place | Holds | Resolved by |
| --- | --- | --- |
| the compiled name table, slot per station | `Gameplay-Devices-Radio-RadioStation*` | the native `GetRadioReceiverStationName` returns it as a `CName`; the UI calls `GetLocalizedTextByKey` |
| `audioRadioTrack.localizationKey` / `primaryLocKey` | the track title key, and its numeric hash | the popup and dashboard, by the numeric key |
| `RadioStationDataProvider.GetChannelName` (script) | the same station key, as a `String` | device UI, `GetLocalizedText` |
| `RadioStation.<x>.displayName` (TweakDB) | `LocKey#<n>` | the radio wheel, `GetLocalizedText` |

`[M]` The vehicle popup compares `GetLocalizedText(record.DisplayName())` with
`GetLocalizedTextByKey(receiverStationName)` to mark the playing station. Both sides must resolve to
the same text.

The framework mints one key per station (`NRF-Station-<name>`) and one per title
(`NRF-Track-<name>-NN`), puts the station key in the name table and the title key in the track row,
and registers the text against them. A manifest never sees a key.

## `onscreens` is sorted and binary-searched

`[M]` `localizationPersistenceOnScreenEntries.entries` in
`base\localization\<lang>\onscreens\onscreens.json` is ordered by `primaryKey`, and a lookup is a
binary search over it. ArchiveXL's own merge does a `std::lower_bound` on `primaryKey`, which is only
correct because the list is sorted.

**A row appended to the end is registered and unreachable.** It is in the array, a dump shows it,
nothing ever resolves it.

A string is registered as two rows, which is what ArchiveXL does:

| Row | `primaryKey` | `secondaryKey` |
| --- | --- | --- |
| 32-bit | `FNV1a32(key)` | the key text |
| 64-bit | `FNV1a64(key)` | empty |

Both inserted at their sorted position. **A `primaryKey` of 0 is indexed by nothing**; ArchiveXL
fills it from the secondary key, and a mod writing rows itself must too.

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
- **`GetLocalizedTextByKey` returns the key itself when nothing matches.** So the in-car stereo prints
  `NRF-Station-radio_station_20_tool`.

## The lookup that still misses

`[M]` With rows inserted in sorted position under both widths, song titles resolve everywhere they
are looked up by numeric hash. The station name, looked up **by key string** through
`GetLocalizedTextByKey` on the dashboard, still prints the key.

`[I]` The by-key path consults an index built when the localization resource is consumed, and the
framework's rows are not in it although they are in the array. Codeware's `ModLocalizationProvider`
registers text that resolves by key everywhere, and is the leading candidate to replace the
hand-rolled insertion. Open as
[issue #5](https://github.com/spuddeh/cp2077-native-radio-framework/issues/5).

## Why nothing is wrapped for a label

Five UI wrappers were written to substitute a station's name at the widget, and deleted once the
name table was found. A wrong label means a table that was not extended, and the rule generalises:
look for another 14-slot array before writing a script wrapper to correct the output. The only
wrappers left are on `RadioStationDataProvider` and `VehiclesManagerDataHelper`, which are game
redscript holding the fourteen as literals with nothing behind them.
