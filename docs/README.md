# Engine measurements

What the framework found out about Cyberpunk 2077's radio system while being built. Everything here
is about the engine, not about this code, so it is useful to anyone extending the radio - RadioXL
included. The code is the proof of the parts that work; these pages are the record of why it is
shaped the way it is, and of what is still unknown.

**Game build 2.31, `Cyberpunk2077.exe`, 59,945,608 bytes.** Every address is an RVA. Nothing in the
plugin uses them; it resolves every site through RED4ext's shipped address database by hash. They
are here to be read.

Every claim carries one of two marks:

- `[M]` **measured** - seen in the binary, in a log, or heard in game.
- `[I]` **inferred** - the best reading of the evidence, not yet checked.

| Page | What it covers |
| --- | --- |
| [The compiled station roster](compiled-station-roster.md) | the two 14-slot tables, their readers, the resolver, the bounds, the three divide-by-fourteen sites, and the patch |
| [The station set and load order](station-set-and-load-order.md) | what a station needs, what kills every radio, the boot-time window, and where a duration has to come from |
| [Labels are localization keys](localization-keys.md) | the name table holds keys, `onscreens` is sorted and binary-searched, and the lookup that still misses |
| [The audio path](audio-path.md) | `mod_sfx_radio`, what AudioXL's renderer does and does not do, and the symptoms that follow from it |
| [The manifest and what is derived from it](manifest-and-derivation.md) | every value a station needs and where the framework gets it, so a manifest never has to carry one |

## Tools that produced these

- **RED4ext's address database**, `cyberpunk2077_addresses.json` beside the executable. One entry per
  address with a hash the maintainers carry across game builds. Every patched site is in it, and the
  roster arrays are resolvable data symbols, so nothing is signature-scanned.
- **Static disassembly** of the executable. No debugger. A station name is an FNV1a64 constant, so the
  roster was found by searching for the hash of `radio_station_12_growl_fm`.
- **The RTTI dump** (NativeDB) for every class and enum named here.
- **SoundDB** (<https://sounddb.redmodding.org>) for what a Wwise event does.
- **AudioXL's source** (<https://github.com/DigitalVixen/cp2077-audio-xl>) for what its renderer does.
- **A probe mod**: a `ScriptableService` with every write behind its own flag, so one variable moved per
  game launch. The nine-variant table on the station-set page came out of it.
