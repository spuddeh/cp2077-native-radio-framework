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

## The vehicle receiver's bound

`[M]` `0x25fdea8` (hash `4148435735`), the vehicle receiver's set-station:

```
+0x5E  83 FF 0E            cmp  edi, 0x0e          ; the requested index against 14  <- imm8
+0x62                      jb   accept
                           mov  edi, [rbx + 0xc]   ; reject: keep the current station
...
+0x85  imul eax, eax, 0x0e ; the next/previous wrap, a second division by 14
```

Rejection is silent: `SetRadioReceiverStation(14)` left the receiver on its old station with no
error. Raising the immediate at `+0x60` makes direct selection work - the car changes station and
plays. `SetRadioReceiverStation` takes the `ERadioStationList` value, not the internal id.

## Exactly three sites divide by fourteen

`[M]` Across the whole binary:

| RVA | What | State |
| --- | --- | --- |
| `0x1c55423` | name-table reader one | erased |
| `0x1cb337d` | name-table reader two, the Radioport's | erased |
| `0x25fdf1b` | the vehicle receiver's next/previous wrap | **not patched** |

The third cannot be handled the same way: it is the tail of a division whose result is used, not a
reduction that can be deleted. Changing its `imul` operand computes the wrong remainder. The fix is
to replace or detour the function. Until then next/previous in a car wraps at fourteen while direct
selection reaches every station.

## The patch

Seven sites across two tables, verified byte for byte first, all abandoned together on a single
mismatch. Two fresh arrays are allocated within rip-relative reach of their readers (the second
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

`[M]` Every hash resolved to the RVA the disassembly predicted, and every radio still works with the
roster at fifteen.

**Both bounds are 8-bit immediates, so 127 stations is the ceiling.** Lifting it means replacing the
readers rather than patching them, which is also what fixes the vehicle wrap.

## Two things this table is not

- **The two specials.** `special_A`, `special_B` and `special_C` at `0x3462A10`, `0x3462A20` and the
  Kurtz accessor's target are the separate handling for none, police and kurtz.
- **The list the UI iterates.** `RadioStationDataProvider` (game redscript) holds the fourteen in
  switch bodies and `VehiclesManagerDataHelper` pushes fifteen literal TweakDB ids. Those are
  script, have no table behind them, and are the only things the framework wraps.
