# The compiled station roster

The fourteen dial stations are not data. They are two 14-slot `CName` arrays in BSS, filled by
startup initialisers, read by a handful of functions that carry the count as an 8-bit immediate,
and reduced modulo fourteen in three places. A fifteenth station needs every one of those extended,
and nothing else: the station itself is then built by the engine like any other.

## The roster - identity

`[M]` **A 14-slot `CName` array at RVA `0x3586d70`, indexed by `ERadioStationList`.** Zero on disk,
filled by an initialiser at `0x13c30` that calls the magic-static CName accessor for each station
name in turn. `ERadioStationList` has 14 members, 0 to 13; `radio_station_police` and
`radio_station_kurtz` are in neither this array nor the enum and are reached by name only.

It has exactly two consumers.

**Name to index, `0x4fe73c`** (RED4ext hash `4164035396`). A leaf function absent from `.pdata`:

```c
bool ResolveStation(CName name, int* out)
{
    if (name == special_A) { *out = 0xff; return true; }        // none
    for (int i = 0; i < 14; i++)                                 // cmp eax, 0x0e  <- imm8
        if (name == roster[i]) { *out = i + 8; return true; }    // add eax, 8
    if (name == special_B) { *out = 0x17; return true; }         // 23
    if (name == special_C) { *out = 0x21; return true; }         // 33
    return false;                                                // *out untouched
}
```

`[M]` **Internal station ids are `ERadioStationList` + 8**, so 8 to 21, with 23 and 33 for the two
non-dial stations and 255 for none. Slot 14 is id 22. All ten callers test the return value, so a
name that misses here fails safely - this is not the function that kills the radios.

**Index to name, `0x6bafe0`** (hash `2956468185`):

```
lea  eax, [rdx - 8]          ; undo the +8 bias
cmp  eax, 0x0d               ; the bound, 13  <- imm8
ja   <abort>
lea  rdx, [0x3586d70]
mov  rax, [rdx + rax*8]
```

## The name table - the label

`[M]` **A second 14-slot `CName` array at `0x3586de0`** (hash `1433472801`), directly after the
roster, filled by an initialiser at `0x13b80` directly before the roster's. Each slot is a
**localization key**, `Gameplay-Devices-Radio-RadioStationAggroIndie` and so on. Not text.

It has two readers, and **both reduce the index modulo fourteen before the bounds check**, so an
unpatched slot 14 reports slot 0's label - Radio Vexelstrom. That was the whole wrong-label bug,
on the dashboard and on the Radioport, and it was never a UI problem.

**Reader one, `0x1c55420`** (hash `2735481579`):

```
+0x00  44 8B C2            mov  r8d, edx           ; the station index
+0x03  B8 25 49 92 24      mov  eax, 0x24924925    \
       ...                                          > magic-number division by 14
+0x16  6B C0 0E            imul eax, eax, 0x0e     /
+0x19  44 2B C0            sub  r8d, eax           ; r8d = index % 14
+0x1C  41 83 F8 0D         cmp  r8d, 0x0d          ; <- imm8
+0x22  48 8D 15 <disp32>   lea  rdx, [0x3586de0]
+0x29  4A 8B 04 C2         mov  rax, [rdx + r8*8]
```

**Reader two, `0x1cb3320`** (hash `131147224`), the Radioport's. Missed for a long time because it
reaches the table as `[r14 + rcx*8 + disp32]` with `r14` holding the image base, not through a
`lea`. The same division, from `+0x5D`, with one difference:

```
+0x5D  B8 25 49 92 24      mov  eax, 0x24924925
+0x62  48 FF 07            inc  qword [rdi]        ; a live side effect INSIDE the division
+0x65  F7 E1               mul  ecx
       ...
+0x72  6B C0 0E            imul eax, eax, 0x0e
+0x75  2B C8               sub  ecx, eax
+0x77  83 F9 0D            cmp  ecx, 0x0d          ; <- imm8
+0x7C  49 8B 9C CE <d32>   mov  rbx, [r14 + rcx*8 + disp32]
```

The `inc` at `+0x62` is not part of the division and must survive, so this block is erased in two
runs of `nop` around it.

**The modulo is removed, not retuned.** The index register already holds the index at the top of
each reader, and `index % 14 == index` for every vanilla index, so erasing the division changes
nothing for the fourteen and stops the wrap for everything past them.

## The vehicle receiver's bound, and its next-station step

`[M]` `0x25fdea8` (hash `4148435735`), the vehicle receiver's set-station:

```
+0x5E  83 FF 0E            cmp  edi, 0x0e          ; the requested index against 14  <- imm8
+0x62                      jb   accept
                           mov  edi, [rbx + 0xc]   ; reject: keep the current station
```

Rejection is silent: `SetRadioReceiverStation(14)` left the receiver on its old station with no
error. Raising the immediate at `+0x60` makes direct selection work - the car changes station and
plays. `SetRadioReceiverStation` takes the `ERadioStationList` value, not the internal id.

`[M]` **The same function's third argument selects the next-station step**, `+0x68` to `+0x92`:

```
+0x68  8B 4B 0C            mov  ecx, [rbx + 0xc]   ; the current ERadioStationList value
+0x6B  E8 <rel32>          call 0x1c554a0          ; enum -> dial position, a switch on 0..13
+0x70  8D 48 01            lea  ecx, [rax + 1]
+0x73  B8 25 49 92 24      mov  eax, 0x24924925    \
       ...                                          > (position + 1) % 14
+0x85  6B C0 0E            imul eax, eax, 0x0e     /
+0x88  2B C8               sub  ecx, eax
+0x8A  E8 <rel32>          call 0x1c553a0          ; dial position -> internal id, a switch on 0..13
+0x8F  8D 78 F8            lea  edi, [rax - 8]     ; undo the id bias
+0x92  89 7B 0C            mov  [rbx + 0xc], edi   ; the new station
```

**A car steps through the dial in frequency order, not enum order.** The two switches are inverse
permutations of the fourteen, and the order they encode is 88.9 to 107.5:

| dial position | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ERadioStationList` | 4 | 0 | 11 | 10 | 1 | 9 | 8 | 6 | 13 | 2 | 3 | 7 | 5 | 12 |

The first switch returns 0 for any value past 13 and the second returns 12 for any position past
13, so a custom station got a wrong answer at both ends before the modulo was reached. The
remainder is used, not discarded, so the division cannot be erased the way the name readers' is,
and its `imul` operand cannot be retuned because the magic constant is 14's own.

**The block is detoured whole.** Its 42 bytes become a `jmp` to a 49-byte stub allocated within
rip-relative reach of the site, followed in the same allocation by two tables of the plugin's own,
`position[total]` and `dial[total]`, made executable before any game byte is written:

```
mov  ecx, [rbx+0xc]
xor  eax, eax
cmp  ecx, total           ; a 32-bit immediate, so this bound is not one of the 8-bit ones
jae  unknown              ; a value off the roster steps from position 0, as vanilla did
lea  rax, [rip+position]
mov  eax, [rax+rcx*4]     ; the dial position
unknown:
inc  eax
xor  edx, edx
mov  ecx, total
div  ecx                  ; edx = (position + 1) % total
lea  rax, [rip+dial]
mov  edi, [rax+rdx*4]     ; the station at that position
jmp  +0x92
```

Register use matches the block it replaces (`ecx`, `eax`, `edx` scratch, `edi` the result, `rbx`
the receiver), and the only entry into the replaced bytes is the `jne` at `+0x5C`, which lands on
the `jmp`.

**The tables hold every station in dial order, custom ones at their frequency.** The fourteen's
order is asked of the game's own switch at patch time, through the `call` target read from the
verified block, so it cannot drift; each custom station is then inserted before the first station
whose frequency is above its own, using the fourteen vanilla frequencies the plugin carries
(`kVanillaFrequency`) and the number at the front of its display name. A custom station with no
number at the front sits after every station that has one, in slot order. The same two tables are
handed to the script-side receivers through `RadioXL_DialPosition` and `RadioXL_DialStation`, so a car, a
world device and the pocket radio step through one dial.

## Exactly three sites divide by fourteen

`[M]` Across the whole binary:

| RVA | What | State |
| --- | --- | --- |
| `0x1c55423` | name-table reader one | erased |
| `0x1cb337d` | name-table reader two, the Radioport's | erased |
| `0x25fdf1b` | the vehicle receiver's next-station wrap | **detoured**, with the block around it |

The third is the tail of a division whose remainder is used, not a reduction that can be deleted,
and the two switches either side of it are wrong for a custom index on their own. It goes with the
whole block, above.

## The patch

Eight sites across two tables and one detour, verified byte for byte first, all abandoned together
on a single mismatch. Two fresh arrays are allocated within rip-relative reach of their readers (the second
name-table reader addresses from the image base, so its table must be within 2 GB of that), the
fourteen vanilla entries are copied, and the custom stations appended.

| Site | Edit |
| --- | --- |
| resolver `lea r8` | displacement to the new roster |
| resolver `cmp eax` | 14 to the new total |
| index-to-name `lea rdx` | displacement to the new roster |
| index-to-name `cmp eax` | 13 to total - 1 |
| vehicle receiver `cmp edi` | 14 to the new total |
| name reader one | division erased, `cmp` to total - 1, `lea rdx` to the new table |
| name reader two | division erased around the `inc`, `cmp` to total - 1, `disp32` to the new table |
| vehicle receiver `+0x68..+0x92` | `jmp` to the next-station stub, which carries the total as an imm32 and the dial tables behind it |

`[M]` Every hash resolved to the RVA the disassembly predicted, and every radio still works with the
roster at fifteen.

**Both roster bounds are 8-bit immediates, so 127 stations is the ceiling.** Lifting it means
replacing the readers rather than patching them. The vehicle step's bound is no longer one of them.

## Two things this table is not

- **The two specials.** `special_A`, `special_B` and `special_C` at `0x3462A10`, `0x3462A20` and the
  Kurtz accessor's target are the separate handling for none, police and kurtz.
- **The list the UI iterates.** `RadioStationDataProvider` (game redscript) holds the fourteen in
  switch bodies and `VehiclesManagerDataHelper` pushes fifteen literal TweakDB ids. Those are
  script, have no table behind them, and are the only things the framework wraps.
