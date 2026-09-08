// ======================================================================================
// Mod Name: Native Radio Framework
// Author: Spuddeh
// Description: Extends the engine's radio station roster so custom stations are real stations.
// File Version: 0.2.0
// Credits: RED4ext by WopsS. AudioXL by DigitalVixen for the plugin shape.
// ======================================================================================
//
// A radio station needs three things and this plugin supplies the first:
//
//   identity    its CName in the engine's station roster - a fixed 14-slot array, extended here
//   membership  its name in audioRadioStationMetadataMap.radioStations - the redscript half
//   content     an audioRadioStationMetadata entry with tracks     - the redscript half
//
// A station that gains membership without identity kills every radio in the game, so the roster is
// patched at plugin load, long before any script runs.
//
// Addresses come from RED4ext's shipped symbol database by hash. The RVAs in the comments are game
// 2.31 and are there to be read, not used.

#include <Windows.h>
#include <RED4ext/RED4ext.hpp>

#include "Duration.hpp"

#include <algorithm>
#include <cstdlib>
#include <cstdint>
#include <cstdio>
#include <cctype>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace
{
// --- addresses, by RED4ext hash ---------------------------------------------------------------
constexpr uint32_t kHashRoster      = 893652571;   // 0x3586d70, the 14-slot CName array
constexpr uint32_t kHashResolve     = 4164035396;  // 0x4fe73c,  name -> index, bound is an imm8
constexpr uint32_t kHashIndexToName = 2956468185;  // 0x6bafe0,  index -> name, bound is an imm8
constexpr uint32_t kHashVehicleSet  = 4148435735;  // 0x25fdea8, the vehicle receiver's set-station
constexpr uint32_t kHashNameTable   = 1433472801;  // 0x3586de0, a SECOND 14-slot CName array
constexpr uint32_t kHashNameReader  = 2735481579;  // 0x1c55420, one reader
constexpr uint32_t kHashNameReader2 = 131147224;   // 0x1cb3320, the OTHER reader - the Radioport's

// --- patch sites, as offsets from those function starts ----------------------------------------
constexpr size_t kResolveLeaOpcode = 0x0B;  // 4C 8D 05   lea r8, [rip+disp32]
constexpr size_t kResolveLeaDisp   = 0x0E;
constexpr size_t kResolveCmpOpcode = 0x1D;  // 83 F8 0E   cmp eax, 14
constexpr size_t kResolveCmpImm    = 0x1F;

constexpr size_t kIndexCmpOpcode = 0x03;  // 83 F8 0D   cmp eax, 13
constexpr size_t kIndexCmpImm    = 0x05;
constexpr size_t kIndexLeaOpcode = 0x0C;  // 48 8D 15   lea rdx, [rip+disp32]
constexpr size_t kIndexLeaDisp   = 0x0F;

constexpr size_t kVehicleCmpOpcode = 0x5E;  // 83 FF 0E   cmp edi, 14
constexpr size_t kVehicleCmpImm    = 0x60;

// The station NAME table's reader, offsets from its own start. It takes the station index in edx
// and reduces it MODULO 14 before the bounds check, so **slot 14 wraps to 0 and a custom station
// reports Radio Vexelstrom's name**. `+0x03` to `+0x1B` is a magic-number division by 14, ending
// in `sub r8d, eax`; `+0x1C` is `cmp r8d, 13`; `+0x22` is the `lea` naming the table.
//
// The division is REMOVED rather than retuned: r8d already holds the index from `+0x00`, and
// `index % 14 == index` for every vanilla index, so erasing it changes nothing for the fourteen.
constexpr size_t kNameMovR8   = 0x00;  // 44 8B C2   mov r8d, edx
constexpr size_t kNameDivFrom = 0x03;  // first byte of the division
constexpr size_t kNameDivTo   = 0x1C;  // one past its last byte
constexpr size_t kNameImul    = 0x16;  // 6B C0 0E   imul eax, eax, 14
constexpr size_t kNameSub     = 0x19;  // 44 2B C0   sub r8d, eax
constexpr size_t kNameCmp     = 0x1C;  // 41 83 F8   cmp r8d, imm8
constexpr size_t kNameCmpImm  = 0x1F;
constexpr size_t kNameLea     = 0x22;  // 48 8D 15   lea rdx, [rip+disp32]
constexpr size_t kNameLeaDisp = 0x25;

constexpr uint8_t kMovR8Edx[] = {0x44, 0x8B, 0xC2};
constexpr uint8_t kMovEaxImm[] = {0xB8, 0x25, 0x49, 0x92, 0x24};
constexpr uint8_t kImulEax14[] = {0x6B, 0xC0, 0x0E};
constexpr uint8_t kSubR8Eax[] = {0x44, 0x2B, 0xC0};
constexpr uint8_t kCmpR8[] = {0x41, 0x83, 0xF8};

// The SECOND reader of the same name table, at 0x1cb3320, offsets from its own start. It is the
// Radioport's, it wraps the index the same way, and it was missed because it reaches the table as
// `[r14 + rcx*8 + disp32]` with r14 holding the image base - not the `lea` form the first uses.
//
// **An `inc qword [rdi]` sits INSIDE the division**, at +0x62, so the block cannot be filled with
// nops in one run without deleting a live side effect. Two runs skip over it.
constexpr size_t kName2MovEax   = 0x5D;  // B8 25 49 92 24   mov eax, 0x24924925
constexpr size_t kName2Keep     = 0x62;  // 48 FF 07         inc qword [rdi]   a live side effect, kept
constexpr size_t kName2DivFrom  = 0x65;  // F7 E1            mul ecx
constexpr size_t kName2DivTo    = 0x77;  // one past `sub ecx, eax`
constexpr size_t kName2Imul     = 0x72;  // 6B C0 0E         imul eax, eax, 14
constexpr size_t kName2Sub      = 0x75;  // 2B C8            sub ecx, eax
constexpr size_t kName2Cmp      = 0x77;  // 83 F9            cmp ecx, imm8
constexpr size_t kName2CmpImm   = 0x79;
constexpr size_t kName2Mov      = 0x7C;  // 49 8B 9C CE      mov rbx, [r14+rcx*8+disp32]
constexpr size_t kName2MovDisp  = 0x80;

constexpr uint8_t kIncRdi[] = {0x48, 0xFF, 0x07};
constexpr uint8_t kMulEcx[] = {0xF7, 0xE1};
constexpr uint8_t kSubEcxEax[] = {0x2B, 0xC8};
constexpr uint8_t kCmpEcx[] = {0x83, 0xF9};
constexpr uint8_t kMovR14Rcx[] = {0x49, 0x8B, 0x9C, 0xCE};

constexpr uint8_t kLeaR8[]  = {0x4C, 0x8D, 0x05};
constexpr uint8_t kLeaRdx[] = {0x48, 0x8D, 0x15};
constexpr uint8_t kCmpEax[] = {0x83, 0xF8};
constexpr uint8_t kCmpEdi[] = {0x83, 0xFF};

constexpr int kVanillaCount = 14;
constexpr int kMaxStations = 127;  // both bounds are 8-bit immediates

// A track is an audio FILE and a title. Nothing else is written by hand: the length is read from
// the file's own headers at load, and AudioXL registers the file and supplies the Wwise id. A
// manifest that carried a duration would be a second place for it to be wrong.
struct Track
{
    std::string file;       // relative to the station's own manifest folder
    std::string title;      // the song title as it is shown, plain text, may be empty
    float duration = 0.0f;  // seconds, from the file's headers - what the station schedules against
};

struct Station
{
    std::string name;         // the station CName, e.g. radio_station_20_tool
    std::string displayName;  // the label the UI shows, plain text
    std::string icon;         // an inkatlas part name, or empty for the framework's own glyph
    std::string atlas;        // the inkatlas resource holding that part, or empty for the framework's
    std::string speaker;      // audioRadioSpeakerType - the station's DJ
    float gain = 0.56f;       // level trim applied to every track's samples, 0..1; see NRF_StationGain
    std::vector<Track> tracks;
    std::string source;       // which manifest it came from, for logging
    std::string folder;       // the manifest's own directory, which track files are relative to
};

// Vanilla puts a LOCALIZATION KEY in the engine's name table and in every audioRadioTrack row, and
// the UI resolves it. So the framework mints a key per station and registers the text against it,
// rather than writing raw text where the game expects something to look up. The key is derived
// from the station name so the plugin and the redscript half agree on it without passing it.
//
// **A key resolves by STRING only under one of the game's three namespaces: `Gameplay-`, `UI-` or
// `Common-`.** The localization manager indexes a key's text through a case-folded path only when it
// starts with one of those (Cyberpunk2077.exe 2.31, the register-entry loop at 0x58ddf0); any other
// key is reachable by hash alone. The dashboard, a world device and `GetLocalizedText` ask by string,
// so the keys sit in the same namespace as the vanilla station keys they stand beside.
std::string StationKey(const std::string& aStation)
{
    return "Gameplay-Devices-Radio-NRF-" + aStation;
}

std::string TwoDigit(size_t aIndex)
{
    const size_t n = aIndex + 1;
    return (n < 10 ? "0" : "") + std::to_string(n);
}

// A track's event name is DERIVED, never written in the manifest. The manifest names an audio file
// and a title; the name AudioXL registers and the station posts is this, so the two cannot drift
// and a filename with a space or an accent in it never reaches an event name.
std::string TrackEvent(const Station& aStation, size_t aIndex)
{
    return aStation.name + "_" + TwoDigit(aIndex);
}

std::string TrackKey(const Station& aStation, size_t aIndex)
{
    return "Gameplay-Devices-Radio_tracks-NRF-" + aStation.name + "-" + TwoDigit(aIndex);
}

std::vector<Station> g_stations;
bool g_patched = false;

const RED4ext::v1::Sdk* g_sdk = nullptr;
RED4ext::v1::PluginHandle g_handle = nullptr;

void Log(const std::string& aText)
{
    if (g_sdk && g_sdk->logger)
    {
        g_sdk->logger->Info(g_handle, aText.c_str());
    }
}

uintptr_t ResolveByHash(uint32_t aHash)
{
    using ResolveFn = uintptr_t (*)(uint32_t);
    static const ResolveFn resolve = []() -> ResolveFn
    {
        const HMODULE red4ext = GetModuleHandleW(L"RED4ext.dll");
        return red4ext ? reinterpret_cast<ResolveFn>(GetProcAddress(red4ext, "RED4ext_ResolveAddress"))
                       : nullptr;
    }();
    return resolve ? resolve(aHash) : 0;
}

// A localization entry with a primaryKey of 0 is not looked up by anything. The game resolves a
// key by its FNV1a32, so the framework supplies that rather than leaving the row unindexed.
uint32_t Fnv1a32(const std::string& aText)
{
    uint32_t hash = 2166136261u;
    for (unsigned char c : aText)
    {
        hash ^= c;
        hash *= 16777619u;
    }
    return hash;
}

uint64_t Fnv1a64(const std::string& aText)
{
    uint64_t hash = 0xcbf29ce484222325ull;
    for (unsigned char c : aText)
    {
        hash ^= c;
        hash *= 0x100000001b3ull;
    }
    return hash;
}

std::string Clock(double aSeconds)
{
    const int whole = static_cast<int>(aSeconds + 0.5);
    return std::to_string(whole / 60) + "m" + (whole % 60 < 10 ? "0" : "") + std::to_string(whole % 60) + "s";
}

// A path's UTF-8 text as a plain string. C++20 makes u8string() a char8_t string.
std::string Utf8(const std::filesystem::path& aPath)
{
    const auto u8 = aPath.u8string();
    return std::string(u8.begin(), u8.end());
}

std::string Hex(uintptr_t aValue)
{
    char buf[32];
    std::snprintf(buf, sizeof(buf), "0x%llx", static_cast<unsigned long long>(aValue));
    return buf;
}

// --- a very small JSON reader -----------------------------------------------------------------
// Only what a station manifest needs: top-level strings and one array of objects. Anything it does
// not understand is ignored rather than rejected, so a manifest can carry fields for later.

// The index of the quote that closes the string literal opening at aOpen, honouring escapes.
size_t JsonStringEnd(const std::string& aText, size_t aOpen)
{
    for (size_t i = aOpen + 1; i < aText.size(); ++i)
    {
        if (aText[i] == '\\')
        {
            ++i;
        }
        else if (aText[i] == '"')
        {
            return i;
        }
    }
    return std::string::npos;
}

// A JSON string literal's value. An escaped backslash becomes one backslash, which a depot path is
// full of; a \u escape outside ASCII becomes UTF-8.
std::string JsonUnescape(const std::string& aRaw)
{
    std::string out;
    out.reserve(aRaw.size());
    for (size_t i = 0; i < aRaw.size(); ++i)
    {
        const char c = aRaw[i];
        if (c != '\\' || i + 1 >= aRaw.size())
        {
            out += c;
            continue;
        }
        const char e = aRaw[++i];
        switch (e)
        {
        case 'n': out += '\n'; break;
        case 't': out += '\t'; break;
        case 'r': out += '\r'; break;
        case 'b': out += '\b'; break;
        case 'f': out += '\f'; break;
        case 'u':
        {
            if (i + 4 >= aRaw.size())
            {
                return out;
            }
            const unsigned code = static_cast<unsigned>(std::strtoul(aRaw.substr(i + 1, 4).c_str(), nullptr, 16));
            i += 4;
            if (code < 0x80)
            {
                out += static_cast<char>(code);
            }
            else if (code < 0x800)
            {
                out += static_cast<char>(0xC0 | (code >> 6));
                out += static_cast<char>(0x80 | (code & 0x3F));
            }
            else
            {
                out += static_cast<char>(0xE0 | (code >> 12));
                out += static_cast<char>(0x80 | ((code >> 6) & 0x3F));
                out += static_cast<char>(0x80 | (code & 0x3F));
            }
            break;
        }
        default: out += e; break;  // backslash, quote, slash, and anything unknown: the character itself
        }
    }
    return out;
}

// A bare number after `"key":` - the manifest's only numeric field. Anything that is not a number,
// or a key that is absent, gives the default.
float JsonNumber(const std::string& aText, const std::string& aKey, float aDefault)
{
    const std::string needle = "\"" + aKey + "\"";
    size_t at = aText.find(needle);
    while (at != std::string::npos)
    {
        size_t cursor = at + needle.size();
        while (cursor < aText.size() && std::isspace(static_cast<unsigned char>(aText[cursor])))
            ++cursor;
        if (cursor < aText.size() && aText[cursor] == ':')
        {
            ++cursor;
            while (cursor < aText.size() && std::isspace(static_cast<unsigned char>(aText[cursor])))
                ++cursor;
            char* end = nullptr;
            const double v = std::strtod(aText.c_str() + cursor, &end);
            if (end && end != aText.c_str() + cursor)
                return static_cast<float>(v);
            return aDefault;
        }
        at = aText.find(needle, at + 1);
    }
    return aDefault;
}

std::string JsonString(const std::string& aText, const std::string& aKey)
{
    const std::string needle = "\"" + aKey + "\"";
    size_t at = aText.find(needle);
    if (at == std::string::npos)
    {
        return {};
    }
    at = aText.find(':', at + needle.size());
    if (at == std::string::npos)
    {
        return {};
    }
    const size_t open = aText.find('"', at);
    if (open == std::string::npos)
    {
        return {};
    }
    const size_t close = JsonStringEnd(aText, open);
    return close == std::string::npos ? std::string() : JsonUnescape(aText.substr(open + 1, close - open - 1));
}

// A depot path uses backslashes. A manifest may write either.
std::string DepotPath(std::string aPath)
{
    for (auto& c : aPath)
    {
        if (c == '/')
        {
            c = '\\';
        }
    }
    return aPath;
}

// tracks: [ { "file": "...", "title": "..." }, ... ]
std::vector<Track> JsonTracks(const std::string& aText)
{
    std::vector<Track> out;
    size_t at = aText.find("\"tracks\"");
    if (at == std::string::npos)
    {
        return out;
    }
    const size_t open = aText.find('[', at);
    if (open == std::string::npos)
    {
        return out;
    }

    // Walks the array one object at a time, stepping over string literals so a title holding a
    // bracket or a brace cannot end the array or an object early.
    size_t cursor = open + 1;
    while (cursor < aText.size())
    {
        const char c = aText[cursor];
        if (c == ']')
        {
            break;
        }
        if (c == '"')
        {
            const size_t end = JsonStringEnd(aText, cursor);
            cursor = end == std::string::npos ? aText.size() : end + 1;
            continue;
        }
        if (c != '{')
        {
            ++cursor;
            continue;
        }
        size_t objClose = cursor + 1;
        while (objClose < aText.size() && aText[objClose] != '}')
        {
            if (aText[objClose] == '"')
            {
                const size_t end = JsonStringEnd(aText, objClose);
                objClose = end == std::string::npos ? aText.size() : end + 1;
                continue;
            }
            ++objClose;
        }
        if (objClose >= aText.size())
        {
            break;
        }
        const std::string chunk = aText.substr(cursor, objClose - cursor + 1);

        Track track;
        track.file = JsonString(chunk, "file");
        track.title = JsonString(chunk, "title");
        if (!track.file.empty())
        {
            out.push_back(track);
        }
        cursor = objClose + 1;
    }
    return out;
}

std::vector<std::string> JsonStringArray(const std::string& aText, const std::string& aKey)
{
    std::vector<std::string> out;
    const std::string needle = "\"" + aKey + "\"";
    size_t at = aText.find(needle);
    if (at == std::string::npos)
    {
        return out;
    }
    const size_t open = aText.find('[', at);
    const size_t close = aText.find(']', open == std::string::npos ? at : open);
    if (open == std::string::npos || close == std::string::npos)
    {
        return out;
    }
    size_t cursor = open;
    while (true)
    {
        const size_t a = aText.find('"', cursor);
        if (a == std::string::npos || a > close)
        {
            break;
        }
        const size_t b = aText.find('"', a + 1);
        if (b == std::string::npos || b > close)
        {
            break;
        }
        out.push_back(aText.substr(a + 1, b - a - 1));
        cursor = b + 1;
    }
    return out;
}

std::filesystem::path PluginDirectory()
{
    HMODULE self = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCWSTR>(&PluginDirectory), &self))
    {
        return {};
    }
    wchar_t path[MAX_PATH]{};
    if (!GetModuleFileNameW(self, path, MAX_PATH))
    {
        return {};
    }
    return std::filesystem::path(path).parent_path();
}

// Every mod drops its own folder, so nothing is shared and nothing can collide.
//   red4ext/plugins/NativeRadioFramework/stations/<ModName>/station.json
void LoadManifests()
{
    const auto root = PluginDirectory() / "stations";
    std::error_code ec;
    if (!std::filesystem::is_directory(root, ec))
    {
        Log("no stations directory - nothing to register");
        return;
    }

    for (const auto& entry : std::filesystem::directory_iterator(root, ec))
    {
        if (!entry.is_directory())
        {
            continue;
        }
        const auto file = entry.path() / "station.json";
        if (!std::filesystem::exists(file, ec))
        {
            continue;
        }

        std::ifstream in(file);
        std::stringstream buffer;
        buffer << in.rdbuf();
        const std::string text = buffer.str();

        Station station;
        station.name = JsonString(text, "name");
        station.displayName = JsonString(text, "displayName");
        station.icon = JsonString(text, "icon");
        station.atlas = DepotPath(JsonString(text, "atlas"));
        station.speaker = JsonString(text, "speaker");
        // The game's custom-radio object sends a world device 3 to 7 dB hotter than any vanilla
        // station, and a master sitting on 0 dBFS wraps in the next 16-bit stage there. 0.56 (-5 dB)
        // lands both of its sends inside the vanilla range. Above 1 there is nothing to gain.
        station.gain = std::clamp(JsonNumber(text, "gain", 0.56f), 0.0f, 1.0f);
        station.tracks = JsonTracks(text);
        station.source = entry.path().filename().string();
        // Kept as UTF-8. A manifest is UTF-8 and a track file may carry any script in its name, and
        // std::filesystem::path(std::string) on Windows reads the system code page, not UTF-8.
        station.folder = Utf8(entry.path());

        if (station.name.empty())
        {
            Log(station.source + ": manifest has no \"name\" - skipped");
            continue;
        }
        // Each file's length, from its headers. The engine reads the event table while it boots,
        // before any audio framework has decoded a file, so this is the only source ready in time.
        // A track with no readable length is dropped: a zero in that table is what makes a station
        // pick a track at random instead of running on the clock.
        double total = 0.0;
        for (auto it = station.tracks.begin(); it != station.tracks.end();)
        {
            it->duration = nrf::AudioDuration(std::filesystem::u8path(station.folder) / std::filesystem::u8path(it->file));
            if (it->duration <= 0.0f)
            {
                Log(station.source + ": '" + it->file +
                    "' has no readable length (missing, or not WAV/MP3/OGG/FLAC) - dropped");
                it = station.tracks.erase(it);
                continue;
            }
            total += it->duration;
            ++it;
        }

        if (station.tracks.empty())
        {
            Log(station.source + ": station '" + station.name +
                "' lists no usable tracks - each needs a \"file\" with a readable length - skipped");
            continue;
        }

        bool duplicate = false;
        for (const auto& known : g_stations)
        {
            if (known.name == station.name)
            {
                Log(station.source + ": station '" + station.name + "' is already registered by " +
                    known.source + " - skipped");
                duplicate = true;
                break;
            }
        }
        if (!duplicate)
        {
            Log(station.source + ": '" + station.name + "' with " +
                std::to_string(station.tracks.size()) + " track(s), " + Clock(total) +
                (station.displayName.empty() ? ", NO displayName - it will show its CName"
                                             : ", '" + station.displayName + "'"));
            g_stations.push_back(std::move(station));
        }
    }
}

// A rip-relative displacement is 32 bits signed, so the new roster has to land within 2 GB of the
// instructions that reach it.
void* AllocateNear(uintptr_t aAnchor, size_t aSize)
{
    SYSTEM_INFO si{};
    GetSystemInfo(&si);
    const uintptr_t step = si.dwAllocationGranularity;

    for (uintptr_t delta = step; delta < 0x7FF00000ull; delta += step)
    {
        if (aAnchor > delta)
        {
            const uintptr_t low = (aAnchor - delta) & ~(step - 1);
            if (void* p = VirtualAlloc(reinterpret_cast<void*>(low), aSize, MEM_COMMIT | MEM_RESERVE,
                                       PAGE_READWRITE))
            {
                return p;
            }
        }
        const uintptr_t high = (aAnchor + delta) & ~(step - 1);
        if (void* p = VirtualAlloc(reinterpret_cast<void*>(high), aSize, MEM_COMMIT | MEM_RESERVE,
                                   PAGE_READWRITE))
        {
            return p;
        }
    }
    return nullptr;
}

bool WriteBytes(void* aAt, const void* aData, size_t aLen)
{
    DWORD old = 0;
    if (!VirtualProtect(aAt, aLen, PAGE_EXECUTE_READWRITE, &old))
    {
        return false;
    }
    std::memcpy(aAt, aData, aLen);
    VirtualProtect(aAt, aLen, old, &old);
    FlushInstructionCache(GetCurrentProcess(), aAt, aLen);
    return true;
}

void PatchRoster()
{
    if (g_stations.empty())
    {
        return;
    }

    const auto roster = reinterpret_cast<uint64_t*>(ResolveByHash(kHashRoster));
    const auto resolve = reinterpret_cast<uint8_t*>(ResolveByHash(kHashResolve));
    const auto indexToName = reinterpret_cast<uint8_t*>(ResolveByHash(kHashIndexToName));
    const auto vehicleSet = reinterpret_cast<uint8_t*>(ResolveByHash(kHashVehicleSet));
    const auto nameTable = reinterpret_cast<uint64_t*>(ResolveByHash(kHashNameTable));
    const auto nameReader = reinterpret_cast<uint8_t*>(ResolveByHash(kHashNameReader));
    const auto nameReader2 = reinterpret_cast<uint8_t*>(ResolveByHash(kHashNameReader2));

    if (!roster || !resolve || !indexToName || !vehicleSet || !nameTable || !nameReader ||
        !nameReader2)
    {
        Log("address resolution failed - is RED4ext's address database present for this build?");
        return;
    }

    // Both tables are filled by startup initialisers. Copying zeroes would erase every station.
    for (int i = 0; i < kVanillaCount; ++i)
    {
        if (nameTable[i] == 0)
        {
            Log("name table slot " + std::to_string(i) + " is empty - too early to patch, abandoned");
            return;
        }
        if (roster[i] == 0)
        {
            Log("roster slot " + std::to_string(i) + " is empty - too early to patch, abandoned");
            return;
        }
    }

    struct Check
    {
        const uint8_t* at;
        const uint8_t* want;
        size_t len;
        const char* what;
    };
    const Check checks[] = {
        {resolve + kResolveLeaOpcode, kLeaR8, sizeof(kLeaR8), "resolve: lea r8, [rip+disp32]"},
        {resolve + kResolveCmpOpcode, kCmpEax, sizeof(kCmpEax), "resolve: cmp eax, imm8"},
        {indexToName + kIndexCmpOpcode, kCmpEax, sizeof(kCmpEax), "indexToName: cmp eax, imm8"},
        {indexToName + kIndexLeaOpcode, kLeaRdx, sizeof(kLeaRdx), "indexToName: lea rdx, [rip+disp32]"},
        {vehicleSet + kVehicleCmpOpcode, kCmpEdi, sizeof(kCmpEdi), "vehicleSet: cmp edi, imm8"},
        {nameReader + kNameMovR8, kMovR8Edx, sizeof(kMovR8Edx), "nameReader: mov r8d, edx"},
        {nameReader + kNameDivFrom, kMovEaxImm, sizeof(kMovEaxImm), "nameReader: mov eax, 0x24924925"},
        {nameReader + kNameImul, kImulEax14, sizeof(kImulEax14), "nameReader: imul eax, eax, 14"},
        {nameReader + kNameSub, kSubR8Eax, sizeof(kSubR8Eax), "nameReader: sub r8d, eax"},
        {nameReader + kNameCmp, kCmpR8, sizeof(kCmpR8), "nameReader: cmp r8d, imm8"},
        {nameReader + kNameLea, kLeaRdx, sizeof(kLeaRdx), "nameReader: lea rdx, [rip+disp32]"},
        {nameReader2 + kName2MovEax, kMovEaxImm, sizeof(kMovEaxImm), "nameReader2: mov eax, 0x24924925"},
        {nameReader2 + kName2Keep, kIncRdi, sizeof(kIncRdi), "nameReader2: inc qword [rdi]"},
        {nameReader2 + kName2DivFrom, kMulEcx, sizeof(kMulEcx), "nameReader2: mul ecx"},
        {nameReader2 + kName2Imul, kImulEax14, sizeof(kImulEax14), "nameReader2: imul eax, eax, 14"},
        {nameReader2 + kName2Sub, kSubEcxEax, sizeof(kSubEcxEax), "nameReader2: sub ecx, eax"},
        {nameReader2 + kName2Cmp, kCmpEcx, sizeof(kCmpEcx), "nameReader2: cmp ecx, imm8"},
        {nameReader2 + kName2Mov, kMovR14Rcx, sizeof(kMovR14Rcx), "nameReader2: mov rbx, [r14+rcx*8+disp32]"},
    };
    for (const auto& c : checks)
    {
        if (std::memcmp(c.at, c.want, c.len) != 0)
        {
            Log(std::string("byte check FAILED at ") + c.what + " - nothing patched");
            return;
        }
    }
    if (resolve[kResolveCmpImm] != kVanillaCount || indexToName[kIndexCmpImm] != kVanillaCount - 1 ||
        vehicleSet[kVehicleCmpImm] != kVanillaCount || nameReader[kNameCmpImm] != kVanillaCount - 1 ||
        nameReader2[kName2CmpImm] != kVanillaCount - 1)
    {
        Log("bounds are not the expected 14/13/14/13/13 - already patched, or a different build. Abandoned.");
        return;
    }

    if (static_cast<int>(g_stations.size()) > kMaxStations - kVanillaCount)
    {
        Log("too many stations - the engine's bounds are 8-bit, so 127 is the ceiling");
        return;
    }

    const int total = kVanillaCount + static_cast<int>(g_stations.size());
    void* fresh = AllocateNear(reinterpret_cast<uintptr_t>(resolve), total * sizeof(uint64_t));
    if (!fresh)
    {
        Log("could not allocate the new roster within rip-relative reach");
        return;
    }

    void* freshNames = AllocateNear(reinterpret_cast<uintptr_t>(nameReader), total * sizeof(uint64_t));
    if (!freshNames)
    {
        Log("could not allocate the new name table within rip-relative reach");
        return;
    }

    auto* table = static_cast<uint64_t*>(fresh);
    std::memcpy(table, roster, kVanillaCount * sizeof(uint64_t));

    // The name table holds a LOCALIZATION KEY, not the label itself - every vanilla slot is a
    // Gameplay-Devices-Radio-RadioStation* key that the UI looks up. Writing raw text here is what
    // made the station selector fail to match: it compares against a resolved string. So each
    // station gets a minted key, and the redscript half registers the text against it.
    auto* names = static_cast<uint64_t*>(freshNames);
    std::memcpy(names, nameTable, kVanillaCount * sizeof(uint64_t));

    for (size_t i = 0; i < g_stations.size(); ++i)
    {
        table[kVanillaCount + i] = Fnv1a64(g_stations[i].name);
        names[kVanillaCount + i] = Fnv1a64(StationKey(g_stations[i].name));
    }

    const int32_t dispResolve =
        static_cast<int32_t>(reinterpret_cast<uintptr_t>(table) -
                             (reinterpret_cast<uintptr_t>(resolve) + kResolveLeaDisp + 4));
    const int32_t dispIndex =
        static_cast<int32_t>(reinterpret_cast<uintptr_t>(table) -
                             (reinterpret_cast<uintptr_t>(indexToName) + kIndexLeaDisp + 4));
    const int32_t dispNames =
        static_cast<int32_t>(reinterpret_cast<uintptr_t>(names) -
                             (reinterpret_cast<uintptr_t>(nameReader) + kNameLeaDisp + 4));
    const uint8_t boundTotal = static_cast<uint8_t>(total);
    const uint8_t boundLast = static_cast<uint8_t>(total - 1);

    // Erasing the modulo leaves r8d holding the index the caller passed, which is what the bounds
    // check below already expects.
    const uint8_t nops[kNameDivTo - kNameDivFrom] = {
        0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
        0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90};

    // The second reader addresses the table from the image base, not from itself, so its
    // displacement is measured from there.
    const auto imageBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    const int64_t fromBase = static_cast<int64_t>(reinterpret_cast<uintptr_t>(names)) -
                             static_cast<int64_t>(imageBase);
    if (!imageBase || fromBase > INT32_MAX || fromBase < INT32_MIN)
    {
        Log("the new name table is out of 32-bit reach of the image base - nothing patched");
        return;
    }
    const int32_t dispNames2 = static_cast<int32_t>(fromBase);

    const uint8_t nops2a[kName2Keep - kName2MovEax] = {0x90, 0x90, 0x90, 0x90, 0x90};
    const uint8_t nops2b[kName2DivTo - kName2DivFrom] = {
        0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
        0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90};

    const bool ok = WriteBytes(resolve + kResolveLeaDisp, &dispResolve, sizeof(dispResolve)) &&
                    WriteBytes(nameReader2 + kName2MovEax, nops2a, sizeof(nops2a)) &&
                    WriteBytes(nameReader2 + kName2DivFrom, nops2b, sizeof(nops2b)) &&
                    WriteBytes(nameReader2 + kName2CmpImm, &boundLast, 1) &&
                    WriteBytes(nameReader2 + kName2MovDisp, &dispNames2, sizeof(dispNames2)) &&
                    WriteBytes(indexToName + kIndexLeaDisp, &dispIndex, sizeof(dispIndex)) &&
                    WriteBytes(nameReader + kNameLeaDisp, &dispNames, sizeof(dispNames)) &&
                    WriteBytes(nameReader + kNameDivFrom, nops, sizeof(nops)) &&
                    WriteBytes(resolve + kResolveCmpImm, &boundTotal, 1) &&
                    WriteBytes(indexToName + kIndexCmpImm, &boundLast, 1) &&
                    WriteBytes(nameReader + kNameCmpImm, &boundLast, 1) &&
                    WriteBytes(vehicleSet + kVehicleCmpImm, &boundTotal, 1);

    if (!ok)
    {
        Log("a write failed - the roster may be half patched, restart the game");
        return;
    }

    g_patched = true;
    for (size_t i = 0; i < g_stations.size(); ++i)
    {
        Log("slot " + std::to_string(kVanillaCount + i) + " (enum " +
            std::to_string(kVanillaCount + i) + ", internal id " +
            std::to_string(kVanillaCount + i + 8) + "): " + g_stations[i].name);
    }
    Log("roster patched to " + std::to_string(total) + " stations at " +
        Hex(reinterpret_cast<uintptr_t>(table)));
}

// --- the script side of the manifest -----------------------------------------------------------
// The redscript half needs the same list, and it must not be declared twice. These hand it over.

// --- the script side of the manifest -----------------------------------------------------------
// Everything the redscript half needs, so the station is declared once in the manifest and read
// twice. String getters return "" and index getters 0 for anything out of range, so a caller that
// loops past the end gets nothing rather than a crash.

namespace
{
const Station* At(int32_t aIndex)
{
    if (!g_patched || aIndex < 0 || aIndex >= static_cast<int32_t>(g_stations.size()))
    {
        return nullptr;
    }
    return &g_stations[aIndex];
}

void OutString(RED4ext::CString* aOut, const std::string& aText)
{
    if (aOut)
    {
        *aOut = RED4ext::CString(aText.c_str());
    }
}
} // namespace

void NRF_StationCount(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    ++aFrame->code;
    if (aOut)
    {
        *aOut = g_patched ? static_cast<int32_t>(g_stations.size()) : 0;
    }
}

void NRF_StationName(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CName* aOut, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(aFrame, &index);
    ++aFrame->code;
    const Station* s = At(index);
    if (aOut)
    {
        *aOut = s ? RED4ext::CName(s->name.c_str()) : RED4ext::CName();
    }
}

void NRF_StationKey(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CName* aOut, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(aFrame, &index);
    ++aFrame->code;
    const Station* s = At(index);
    if (aOut)
    {
        *aOut = s ? RED4ext::CName(StationKey(s->name).c_str()) : RED4ext::CName();
    }
}

void NRF_StationDisplayName(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(aFrame, &index);
    ++aFrame->code;
    const Station* s = At(index);
    OutString(aOut, s ? (s->displayName.empty() ? s->name : s->displayName) : std::string());
}

void NRF_StationIcon(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(aFrame, &index);
    ++aFrame->code;
    const Station* s = At(index);
    OutString(aOut, s ? s->icon : std::string());
}

void NRF_StationAtlas(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(aFrame, &index);
    ++aFrame->code;
    const Station* s = At(index);
    OutString(aOut, s ? s->atlas : std::string());
}

void NRF_StationSpeaker(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(aFrame, &index);
    ++aFrame->code;
    const Station* s = At(index);
    OutString(aOut, s ? s->speaker : std::string());
}

// The level trim for every track of a station, applied through AudioXL's SetGain once the row
// exists. RegisterSoundEx's own gain argument is stored in the engine's registry entry and never
// reaches the samples, so it is not the way to set this.
void NRF_StationGain(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, float* aOut, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(aFrame, &index);
    ++aFrame->code;
    const Station* s = At(index);
    if (aOut)
        *aOut = s ? s->gain : 0.56f;
}

void NRF_StationTrackCount(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(aFrame, &index);
    ++aFrame->code;
    const Station* s = At(index);
    if (aOut)
    {
        *aOut = s ? static_cast<int32_t>(s->tracks.size()) : 0;
    }
}

void NRF_StationTrack(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CName* aOut, int64_t)
{
    int32_t index = -1;
    int32_t track = -1;
    RED4ext::GetParameter(aFrame, &index);
    RED4ext::GetParameter(aFrame, &track);
    ++aFrame->code;
    if (!aOut)
    {
        return;
    }
    const Station* s = At(index);
    *aOut = (s && track >= 0 && track < static_cast<int32_t>(s->tracks.size()))
                ? RED4ext::CName(TrackEvent(*s, track).c_str())
                : RED4ext::CName();
}

void NRF_StationTrackKey(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CName* aOut, int64_t)
{
    int32_t index = -1;
    int32_t track = -1;
    RED4ext::GetParameter(aFrame, &index);
    RED4ext::GetParameter(aFrame, &track);
    ++aFrame->code;
    if (!aOut)
    {
        return;
    }
    const Station* s = At(index);
    *aOut = (s && track >= 0 && track < static_cast<int32_t>(s->tracks.size()))
                ? RED4ext::CName(TrackKey(*s, track).c_str())
                : RED4ext::CName();
}

// An absolute path, because AudioXL's RegisterSound takes one and the station mod's folder is the
// only place the file is known to be.
void NRF_StationTrackFile(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    int32_t index = -1;
    int32_t track = -1;
    RED4ext::GetParameter(aFrame, &index);
    RED4ext::GetParameter(aFrame, &track);
    ++aFrame->code;
    const Station* s = At(index);
    if (s && track >= 0 && track < static_cast<int32_t>(s->tracks.size()))
    {
        const auto full = std::filesystem::u8path(s->folder) / std::filesystem::u8path(s->tracks[track].file);
        OutString(aOut, Utf8(full));
        return;
    }
    OutString(aOut, std::string());
}

// Seconds, from the file's headers: the event table row's duration, which the station schedules
// its next track against.
void NRF_StationTrackDuration(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, float* aOut, int64_t)
{
    int32_t index = -1;
    int32_t track = -1;
    RED4ext::GetParameter(aFrame, &index);
    RED4ext::GetParameter(aFrame, &track);
    ++aFrame->code;
    const Station* s = At(index);
    if (aOut)
    {
        *aOut = (s && track >= 0 && track < static_cast<int32_t>(s->tracks.size()))
                    ? s->tracks[track].duration
                    : 0.0f;
    }
}

// The value a localization row is INDEXED by. A row whose primaryKey is 0 resolves for nothing.
void NRF_StationKeyHash(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, uint64_t* aOut, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(aFrame, &index);
    ++aFrame->code;
    const Station* s = At(index);
    if (aOut)
    {
        *aOut = s ? Fnv1a32(StationKey(s->name)) : 0;
    }
}

void NRF_StationTrackKeyHash(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, uint64_t* aOut, int64_t)
{
    int32_t index = -1;
    int32_t track = -1;
    RED4ext::GetParameter(aFrame, &index);
    RED4ext::GetParameter(aFrame, &track);
    ++aFrame->code;
    if (!aOut)
    {
        return;
    }
    const Station* s = At(index);
    *aOut = (s && track >= 0 && track < static_cast<int32_t>(s->tracks.size()))
                ? Fnv1a32(TrackKey(*s, track))
                : 0;
}

// The 64-bit width of the same key. The game keeps its localization rows sorted by primaryKey and
// finds one by binary search, and a key is registered under both widths so either resolves.
void NRF_StationKeyHash64(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, uint64_t* aOut, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(aFrame, &index);
    ++aFrame->code;
    const Station* s = At(index);
    if (aOut)
    {
        *aOut = s ? Fnv1a64(StationKey(s->name)) : 0;
    }
}

void NRF_StationTrackKeyHash64(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, uint64_t* aOut, int64_t)
{
    int32_t index = -1;
    int32_t track = -1;
    RED4ext::GetParameter(aFrame, &index);
    RED4ext::GetParameter(aFrame, &track);
    ++aFrame->code;
    if (!aOut)
    {
        return;
    }
    const Station* s = At(index);
    *aOut = (s && track >= 0 && track < static_cast<int32_t>(s->tracks.size()))
                ? Fnv1a64(TrackKey(*s, track))
                : 0;
}

void NRF_StationTrackTitle(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    int32_t index = -1;
    int32_t track = -1;
    RED4ext::GetParameter(aFrame, &index);
    RED4ext::GetParameter(aFrame, &track);
    ++aFrame->code;
    const Station* s = At(index);
    OutString(aOut, (s && track >= 0 && track < static_cast<int32_t>(s->tracks.size()))
                        ? s->tracks[track].title
                        : std::string());
}

// A CName built from a string carries the hash but not the string, so anything that prints or
// resolves it by text sees nothing. Registering the pair costs nothing and makes logs readable.
void PoolNames()
{
    for (const auto& station : g_stations)
    {
        RED4ext::CNamePool::Add(station.name.c_str());
        RED4ext::CNamePool::Add(StationKey(station.name).c_str());
        for (size_t i = 0; i < station.tracks.size(); ++i)
        {
            RED4ext::CNamePool::Add(TrackEvent(station, i).c_str());
            RED4ext::CNamePool::Add(TrackKey(station, i).c_str());
        }
    }
}

void RegisterNatives()
{
    PoolNames();

    auto* rtti = RED4ext::CRTTISystem::Get();

    // Each native has its own return type, so registration goes through a template rather than a
    // table of void pointers - CGlobalFunction::Create deduces the signature from the function.
    const auto reg = [rtti](const char* aName, auto aFn, const char* aReturn, int aParams)
    {
        const std::string full = std::string("NativeRadioFramework.") + aName;
        auto* fn = RED4ext::CGlobalFunction::Create(full.c_str(), aName, aFn);
        fn->flags.isNative = true;
        if (aParams >= 1)
        {
            fn->AddParam("Int32", "index");
        }
        if (aParams >= 2)
        {
            fn->AddParam("Int32", "track");
        }
        fn->SetReturnType(aReturn);
        rtti->RegisterFunction(fn);
    };

    reg("NRF_StationCount", &NRF_StationCount, "Int32", 0);
    reg("NRF_StationName", &NRF_StationName, "CName", 1);
    reg("NRF_StationKey", &NRF_StationKey, "CName", 1);
    reg("NRF_StationDisplayName", &NRF_StationDisplayName, "String", 1);
    reg("NRF_StationIcon", &NRF_StationIcon, "String", 1);
    reg("NRF_StationAtlas", &NRF_StationAtlas, "String", 1);
    reg("NRF_StationSpeaker", &NRF_StationSpeaker, "String", 1);
    reg("NRF_StationGain", &NRF_StationGain, "Float", 1);
    reg("NRF_StationTrackCount", &NRF_StationTrackCount, "Int32", 1);
    reg("NRF_StationTrack", &NRF_StationTrack, "CName", 2);
    reg("NRF_StationTrackKey", &NRF_StationTrackKey, "CName", 2);
    reg("NRF_StationTrackFile", &NRF_StationTrackFile, "String", 2);
    reg("NRF_StationTrackTitle", &NRF_StationTrackTitle, "String", 2);
    reg("NRF_StationTrackDuration", &NRF_StationTrackDuration, "Float", 2);
    reg("NRF_StationKeyHash", &NRF_StationKeyHash, "Uint64", 1);
    reg("NRF_StationTrackKeyHash", &NRF_StationTrackKeyHash, "Uint64", 2);
    reg("NRF_StationKeyHash64", &NRF_StationKeyHash64, "Uint64", 1);
    reg("NRF_StationTrackKeyHash64", &NRF_StationTrackKeyHash64, "Uint64", 2);
}
} // namespace

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"NativeRadioFramework";
    aInfo->author = L"Spuddeh";
    aInfo->version = RED4EXT_V1_SEMVER(0, 2, 0);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_LATEST;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle,
                                        RED4ext::v1::EMainReason aReason, const RED4ext::v1::Sdk* aSdk)
{
    if (aReason == RED4ext::v1::EMainReason::Load)
    {
        g_sdk = aSdk;
        g_handle = aHandle;

        LoadManifests();
        PatchRoster();

        RED4ext::CRTTISystem::Get()->AddRegisterCallback(&RegisterNatives);
    }
    return true;
}
