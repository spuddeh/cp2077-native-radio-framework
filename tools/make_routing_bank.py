r"""Build the soundbank that defines this framework's own custom-sound type.

A custom sound is played by posting its TYPE's event, and the type is whatever a loaded bank
defines. `mod_sfx_radio` is the game's own type for this and it works, but its stereo Broadcast Send
is trimmed +2.9 dB, which is 3 to 7 dB above every vanilla station and is where the crackle at a
world device comes from.

This clones that type's three objects - Event, Play action and CAkSound - and cites a vanilla
station's pair of Broadcast Send objects in place of `mod_sfx_radio`'s own. Nothing else changes:
the Wwise Audio Input source, the positioning bits, the Time Stretch insert, the `volume_music`
RTPC, the -96 dB dry mute and the parent are the bytes they already were.

**Only the two sends are swapped, and that is deliberate.** A send object carries no station
identity - all 28 stereo sends and all 27 mono sends in the game map their channel RTPC identically,
and only the `radio_broadcast_mute` trim at x = 0 differs - so citing a station's send borrows its
level and nothing else. The bus is left alone because the dry path it feeds is muted at -96 dB.

**Keeping both sends and the dry mute is what keeps the receivers' behaviour.** A device switched
off or retuned stops listening rather than stopping the voice, and a car takes a station over from
the Radioport by the same arbitration, so a sound stays under the radio system's control for as long
as it stays on the broadcast chain.

Run:  python make_routing_bank.py <mod.bnk> <radio.bnk> <out.bnk>
"""
import struct
import sys

# The chain that plays a custom sound of type `mod_sfx_radio`, in the game's own `mod.bnk`.
TEMPLATE_EVENT = 2845221403   # FNV-1 32 of "mod_sfx_radio"
TEMPLATE_BANK = 1082004799    # mod.bnk's own id, cited by the Play action

# `mod_sfx_radio`'s own pair, the two ids being replaced.
MOD_SFX_STEREO = 385769109    # +2.9 dB, world devices
MOD_SFX_MONO = 772871769      # -2.0 dB, the Radioport

# Radio Vexelstrom's pair: -2.0 dB stereo and -5.0 dB mono, the middle of the dial on both sends.
# A framework's default belongs mid-dial so a custom station sounds like an average station rather
# than the quietest one. A station manifest's `gain` remains the per-station override.
#
# **These are COPIED into this bank rather than cited from radio.bnk.** A cited id that a game patch
# or another mod moves does not error: the effect is simply absent, the sound leaves the broadcast
# chain, and it plays its dry output about 15 dB hot at every distance while every script-side check
# still passes. A copy cannot be moved out from under it.
#
# What a copy gives up is tracking: a retuned vanilla dial no longer moves these. Re-derive the
# trims after a game patch and rebuild - the method is in the mod's docs.
STATION_STEREO = 813819638
STATION_MONO = 870978591

TYPE_NAME = "nrf_radio"
BANK_NAME = "nrf_routing"

BANK_VERSION = 150
LANGUAGE_ID = 393239870

HIRC_EVENT = 4
HIRC_ACTION = 3
HIRC_SOUND = 2


def fnv(name):
    h = 2166136261
    for b in name.lower().encode():
        h = (h * 16777619) & 0xFFFFFFFF
        h ^= b
    return h


def read_hirc(path):
    data = open(path, "rb").read()
    offset = 0
    while offset < len(data) - 8:
        if data[offset:offset + 4] == b"HIRC":
            break
        offset += 8 + struct.unpack_from("<I", data, offset + 4)[0]
    pos = offset + 8
    count = struct.unpack_from("<I", data, pos)[0]
    pos += 4
    objects = {}
    for _ in range(count):
        size = struct.unpack_from("<I", data, pos + 1)[0]
        obj_id = struct.unpack_from("<I", data, pos + 5)[0]
        objects[obj_id] = (data[pos], data[pos + 5:pos + 5 + size])
        pos += 5 + size
    return objects


def replace_u32(buf, old, new):
    hits = 0
    for i in range(len(buf) - 3):
        if struct.unpack_from("<I", buf, i)[0] == old:
            struct.pack_into("<I", buf, i, new)
            hits += 1
    return hits


def object_bytes(obj_type, body):
    return bytes([obj_type]) + struct.pack("<I", len(body)) + bytes(body)


def build(mod_path, radio_path):
    mod = read_hirc(mod_path)
    radio = read_hirc(radio_path)

    for send in (STATION_STEREO, STATION_MONO):
        assert send in radio, f"send {send} is not in radio.bnk - the game's ids have moved"

    bank_id = fnv(BANK_NAME)
    event_id = fnv(TYPE_NAME)
    action_id = fnv(TYPE_NAME + "_action")
    sound_id = fnv(TYPE_NAME + "_sound")
    stereo_id = fnv(TYPE_NAME + "_send_stereo")
    mono_id = fnv(TYPE_NAME + "_send_mono")

    event_type, event_body = mod[TEMPLATE_EVENT]
    assert event_type == HIRC_EVENT and event_body[4] == 1, "the template event is not a single-action event"
    template_action = struct.unpack_from("<I", event_body, 5)[0]

    action_type, action_body = mod[template_action]
    assert action_type == HIRC_ACTION, "the template event does not point at an action"
    template_sound = struct.unpack_from("<I", action_body, 6)[0]

    sound_type, sound_body = mod[template_sound]
    assert sound_type == HIRC_SOUND, "the template action does not target a sound"

    event = bytearray(event_body)
    struct.pack_into("<I", event, 0, event_id)
    struct.pack_into("<I", event, 5, action_id)

    action = bytearray(action_body)
    struct.pack_into("<I", action, 0, action_id)
    assert replace_u32(action, template_sound, sound_id) == 1, "the action cites its target more than once"
    assert replace_u32(action, TEMPLATE_BANK, bank_id) == 1, "the action cites its bank more than once"

    sound = bytearray(sound_body)
    struct.pack_into("<I", sound, 0, sound_id)
    assert replace_u32(sound, MOD_SFX_STEREO, stereo_id) == 1, "the sound cites its stereo send more than once"
    assert replace_u32(sound, MOD_SFX_MONO, mono_id) == 1, "the sound cites its mono send more than once"

    # A send's only station-specific content is one curve point - `radio_broadcast_mute` at x = 0,
    # which is the station's standing level. Everything else, the channel curves included, is
    # identical across all 55 sends in the game. So a copy carrying a new id behaves exactly as the
    # original, and the mute the engine applies on combat or a device switching off still reaches it.
    sends = b""
    for source, new_id in ((STATION_STEREO, stereo_id), (STATION_MONO, mono_id)):
        send_type, send_body = radio[source]
        body = bytearray(send_body)
        struct.pack_into("<I", body, 0, new_id)
        sends += object_bytes(send_type, body)

    hirc = sends
    hirc += object_bytes(HIRC_SOUND, sound)
    hirc += object_bytes(HIRC_ACTION, action)
    hirc += object_bytes(HIRC_EVENT, event)
    hirc = struct.pack("<I", 5) + hirc

    bkhd = struct.pack("<IIIIII", BANK_VERSION, bank_id, LANGUAGE_ID, 16, 476, 0)
    bkhd += struct.pack("<IIII", bank_id, 1, 0, 0)

    data = b"BKHD" + struct.pack("<I", len(bkhd)) + bkhd
    data += b"HIRC" + struct.pack("<I", len(hirc)) + hirc
    return data, dict(bank=bank_id, event=event_id, action=action_id, sound=sound_id,
                      send_stereo=stereo_id, send_mono=mono_id)


if __name__ == "__main__":
    mod_path, radio_path, out_path = sys.argv[1:4]
    data, ids = build(mod_path, radio_path)
    open(out_path, "wb").write(data)
    print(f"{out_path}: {len(data)} bytes")
    print(f"  type      {TYPE_NAME}")
    for key, value in ids.items():
        print(f"  {key:9} {value}")
