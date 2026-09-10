"""Convert a RadioExt station folder into a RadioXL station.

usage: python radioext-to-radioxl.py <radioExt station dir> <output mod dir> <station cname> [--wav] [--rate 48000]

<radioExt station dir>  the folder holding metadata.json and the audio files, e.g.
                        .../cyber_engine_tweaks/mods/radioExt/radios/phonkwave_radio
<output mod dir>        a mod folder; the station lands in
                        red4ext/plugins/RadioXL/stations/<folder name>/
<station cname>         the station's CName, e.g. radio_station_21_phonkwave

RadioExt's metadata carries displayName, fm, order, customIcon {inkAtlasPath, inkAtlasPart} and a
stream URL. The display name is kept as written (RadioExt puts the frequency at the front, which is
what the framework sorts on). The icon fields map straight across; the atlas stays in the station's
own archive. Song titles are the file names without extension, which is what RadioExt shows. An
`order` list is honoured first, then the remaining files alphabetically. Streams are not supported.

Audio is copied as-is, or with --wav transcoded to 16-bit PCM WAV at --rate (default 48000) with
ffmpeg, which must be on PATH.
"""
import json
import os
import shutil
import subprocess
import sys

AUDIO = (".mp3", ".wav", ".ogg", ".flac")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    argv = sys.argv[1:]
    to_wav = "--wav" in argv
    rate = "48000"
    if "--rate" in argv:
        rate = argv[argv.index("--rate") + 1]
        del argv[argv.index("--rate"):argv.index("--rate") + 2]
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 3:
        print(__doc__)
        sys.exit(2)
    src, out_mod, cname = args

    meta = json.load(open(os.path.join(src, "metadata.json"), encoding="utf-8"))
    if meta.get("streamInfo", {}).get("isStream"):
        print("this station is a web stream; the framework does not play streams")
        sys.exit(1)

    files = sorted(f for f in os.listdir(src) if f.lower().endswith(AUDIO))
    ordered = [f for f in meta.get("order", []) if f in files]
    files = ordered + [f for f in files if f not in ordered]

    station_dir = os.path.join(out_mod, "red4ext", "plugins", "RadioXL", "stations",
                               os.path.basename(os.path.normpath(src)))
    audio_dir = os.path.join(station_dir, "audio")
    os.makedirs(audio_dir, exist_ok=True)

    tracks = []
    for f in files:
        title = os.path.splitext(f)[0]
        if to_wav:
            dst = os.path.splitext(f)[0] + ".wav"
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", os.path.join(src, f),
                            "-ar", rate, "-ac", "2", "-c:a", "pcm_s16le",
                            os.path.join(audio_dir, dst)], check=True)
        else:
            dst = f
            shutil.copy2(os.path.join(src, f), os.path.join(audio_dir, dst))
        tracks.append({"file": "audio/" + dst, "title": title})
        print("  ", dst)

    manifest = {
        "name": cname,
        "displayName": meta.get("displayName", cname),
        "speaker": "None",
        "tracks": tracks,
    }
    icon = meta.get("customIcon") or {}
    if icon.get("useCustom") and icon.get("inkAtlasPath"):
        manifest["icon"] = icon.get("inkAtlasPart", "")
        manifest["atlas"] = icon["inkAtlasPath"]

    with open(os.path.join(station_dir, "station.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(manifest, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    print(f"{len(tracks)} track(s) -> {station_dir}")


if __name__ == "__main__":
    main()
