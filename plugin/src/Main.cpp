// ======================================================================================
// Mod Name: Native Radio Framework
// Author: Spuddeh
// Description: Extends the engine's radio station roster so custom stations are real stations.
// File Version: 0.1.0
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

constexpr uint8_t kLeaR8[]  = {0x4C, 0x8D, 0x05};
constexpr uint8_t kLeaRdx[] = {0x48, 0x8D, 0x15};
constexpr uint8_t kCmpEax[] = {0x83, 0xF8};
constexpr uint8_t kCmpEdi[] = {0x83, 0xFF};

constexpr int kVanillaCount = 14;
constexpr int kMaxStations = 127;  // both bounds are 8-bit immediates

// An event has to be registered in eventsmetadata before the station can post it by name, and the
// duration there is what the station schedules the next track against. Both come from the manifest.
struct Track
{
    std::string event;
    float duration = 0.0f;  // seconds, the audible length
};

struct Station
{
    std::string name;         // the station CName, e.g. radio_station_20_hangouts
    std::string record;       // the TweakDB RadioStation record carrying its name, icon and dial slot
    std::string speaker;      // audioRadioSpeakerType - the station's DJ
    std::vector<Track> tracks;
    std::string source;       // which manifest it came from, for logging
};

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

// Wwise ids are FNV-1 32-bit of the lowercased name - multiply then xor, the opposite order to the
// FNV-1a used for CNames. Getting the two the wrong way round produces an id that resolves to
// nothing, silently.
uint32_t Fnv1_32(const std::string& aText)
{
    uint32_t hash = 2166136261u;
    for (unsigned char c : aText)
    {
        hash *= 16777619u;
        hash ^= static_cast<unsigned char>(std::tolower(c));
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

std::string Hex(uintptr_t aValue)
{
    char buf[32];
    std::snprintf(buf, sizeof(buf), "0x%llx", static_cast<unsigned long long>(aValue));
    return buf;
}

// --- a very small JSON reader -----------------------------------------------------------------
// Only what a station manifest needs: top-level strings and one array of strings. Anything it does
// not understand is ignored rather than rejected, so a manifest can carry fields for later.
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
    const size_t close = aText.find('"', open + 1);
    return close == std::string::npos ? std::string() : aText.substr(open + 1, close - open - 1);
}

// tracks: [ { "event": "...", "duration": 0.0 }, ... ]
std::vector<Track> JsonTracks(const std::string& aText)
{
    std::vector<Track> out;
    size_t at = aText.find("\"tracks\"");
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
        const size_t objOpen = aText.find('{', cursor);
        if (objOpen == std::string::npos || objOpen > close)
        {
            break;
        }
        const size_t objClose = aText.find('}', objOpen);
        if (objClose == std::string::npos || objClose > close)
        {
            break;
        }
        const std::string chunk = aText.substr(objOpen, objClose - objOpen + 1);

        Track track;
        track.event = JsonString(chunk, "event");
        const size_t d = chunk.find("\"duration\"");
        if (d != std::string::npos)
        {
            const size_t colon = chunk.find(':', d);
            if (colon != std::string::npos)
            {
                track.duration = static_cast<float>(std::atof(chunk.c_str() + colon + 1));
            }
        }
        if (!track.event.empty() && track.duration > 0.0f)
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
        station.record = JsonString(text, "record");
        station.speaker = JsonString(text, "speaker");
        station.tracks = JsonTracks(text);
        station.source = entry.path().filename().string();

        if (station.name.empty())
        {
            Log(station.source + ": manifest has no \"name\" - skipped");
            continue;
        }
        if (station.tracks.empty())
        {
            Log(station.source + ": station '" + station.name +
                "' lists no usable tracks - each needs an \"event\" and a non-zero \"duration\" - skipped");
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
                std::to_string(station.tracks.size()) + " track(s)" +
                (station.record.empty() ? ", NO record - it will not reach the dial"
                                        : ", record " + station.record));
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

    if (!roster || !resolve || !indexToName || !vehicleSet)
    {
        Log("address resolution failed - is RED4ext's address database present for this build?");
        return;
    }

    // The roster is filled by a startup initialiser. Copying zeroes would erase every station.
    for (int i = 0; i < kVanillaCount; ++i)
    {
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
        vehicleSet[kVehicleCmpImm] != kVanillaCount)
    {
        Log("bounds are not the expected 14/13/14 - already patched, or a different build. Abandoned.");
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

    auto* table = static_cast<uint64_t*>(fresh);
    std::memcpy(table, roster, kVanillaCount * sizeof(uint64_t));
    for (size_t i = 0; i < g_stations.size(); ++i)
    {
        table[kVanillaCount + i] = Fnv1a64(g_stations[i].name);
    }

    const int32_t dispResolve =
        static_cast<int32_t>(reinterpret_cast<uintptr_t>(table) -
                             (reinterpret_cast<uintptr_t>(resolve) + kResolveLeaDisp + 4));
    const int32_t dispIndex =
        static_cast<int32_t>(reinterpret_cast<uintptr_t>(table) -
                             (reinterpret_cast<uintptr_t>(indexToName) + kIndexLeaDisp + 4));
    const uint8_t boundTotal = static_cast<uint8_t>(total);
    const uint8_t boundLast = static_cast<uint8_t>(total - 1);

    const bool ok = WriteBytes(resolve + kResolveLeaDisp, &dispResolve, sizeof(dispResolve)) &&
                    WriteBytes(indexToName + kIndexLeaDisp, &dispIndex, sizeof(dispIndex)) &&
                    WriteBytes(resolve + kResolveCmpImm, &boundTotal, 1) &&
                    WriteBytes(indexToName + kIndexCmpImm, &boundLast, 1) &&
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
    if (aOut)
    {
        *aOut = (g_patched && index >= 0 && index < static_cast<int32_t>(g_stations.size()))
                    ? RED4ext::CName(g_stations[index].name.c_str())
                    : RED4ext::CName();
    }
}

void NRF_StationTrackCount(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(aFrame, &index);
    ++aFrame->code;
    if (aOut)
    {
        *aOut = (g_patched && index >= 0 && index < static_cast<int32_t>(g_stations.size()))
                    ? static_cast<int32_t>(g_stations[index].tracks.size())
                    : 0;
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
    *aOut = RED4ext::CName();
    if (g_patched && index >= 0 && index < static_cast<int32_t>(g_stations.size()))
    {
        const auto& tracks = g_stations[index].tracks;
        if (track >= 0 && track < static_cast<int32_t>(tracks.size()))
        {
            *aOut = RED4ext::CName(tracks[track].event.c_str());
        }
    }
}

void NRF_StationSpeaker(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(aFrame, &index);
    ++aFrame->code;
    if (aOut)
    {
        *aOut = (g_patched && index >= 0 && index < static_cast<int32_t>(g_stations.size()))
                    ? RED4ext::CString(g_stations[index].speaker.c_str())
                    : RED4ext::CString("");
    }
}

void NRF_StationRecord(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    int32_t index = -1;
    RED4ext::GetParameter(aFrame, &index);
    ++aFrame->code;
    if (aOut)
    {
        *aOut = (g_patched && index >= 0 && index < static_cast<int32_t>(g_stations.size()))
                    ? RED4ext::CString(g_stations[index].record.c_str())
                    : RED4ext::CString("");
    }
}

void NRF_StationTrackDuration(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, float* aOut, int64_t)
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
    *aOut = 0.0f;
    if (g_patched && index >= 0 && index < static_cast<int32_t>(g_stations.size()))
    {
        const auto& tracks = g_stations[index].tracks;
        if (track >= 0 && track < static_cast<int32_t>(tracks.size()))
        {
            *aOut = tracks[track].duration;
        }
    }
}

void NRF_StationTrackWwiseId(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, uint32_t* aOut, int64_t)
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
    *aOut = 0;
    if (g_patched && index >= 0 && index < static_cast<int32_t>(g_stations.size()))
    {
        const auto& tracks = g_stations[index].tracks;
        if (track >= 0 && track < static_cast<int32_t>(tracks.size()))
        {
            *aOut = Fnv1_32(tracks[track].event);
        }
    }
}

// The redscript half declares these inside `module NativeRadioFramework`, so the name it resolves
// is module-qualified. Registering them bare fails script validation with "Missing native global
// function", which stops every redscript mod on the machine from compiling - not just this one.
// A CName built from a string carries the hash but not the string, so anything that prints or
// resolves it by text sees nothing. Registering the pair costs nothing and makes logs readable.
void PoolNames()
{
    for (const auto& station : g_stations)
    {
        RED4ext::CNamePool::Add(station.name.c_str());
        for (const auto& track : station.tracks)
        {
            RED4ext::CNamePool::Add(track.event.c_str());
        }
    }
}

void RegisterNatives()
{
    PoolNames();

    auto* rtti = RED4ext::CRTTISystem::Get();

    auto* count = RED4ext::CGlobalFunction::Create("NativeRadioFramework.NRF_StationCount", "NRF_StationCount", &NRF_StationCount);
    count->flags.isNative = true;
    count->SetReturnType("Int32");
    rtti->RegisterFunction(count);

    auto* name = RED4ext::CGlobalFunction::Create("NativeRadioFramework.NRF_StationName", "NRF_StationName", &NRF_StationName);
    name->flags.isNative = true;
    name->AddParam("Int32", "index");
    name->SetReturnType("CName");
    rtti->RegisterFunction(name);

    auto* trackCount =
        RED4ext::CGlobalFunction::Create("NativeRadioFramework.NRF_StationTrackCount", "NRF_StationTrackCount", &NRF_StationTrackCount);
    trackCount->flags.isNative = true;
    trackCount->AddParam("Int32", "index");
    trackCount->SetReturnType("Int32");
    rtti->RegisterFunction(trackCount);

    auto* track = RED4ext::CGlobalFunction::Create("NativeRadioFramework.NRF_StationTrack", "NRF_StationTrack", &NRF_StationTrack);
    track->flags.isNative = true;
    track->AddParam("Int32", "index");
    track->AddParam("Int32", "track");
    track->SetReturnType("CName");
    rtti->RegisterFunction(track);

    auto* record = RED4ext::CGlobalFunction::Create("NativeRadioFramework.NRF_StationRecord",
                                                    "NRF_StationRecord", &NRF_StationRecord);
    record->flags.isNative = true;
    record->AddParam("Int32", "index");
    record->SetReturnType("String");
    rtti->RegisterFunction(record);

    auto* speaker = RED4ext::CGlobalFunction::Create("NativeRadioFramework.NRF_StationSpeaker",
                                                     "NRF_StationSpeaker", &NRF_StationSpeaker);
    speaker->flags.isNative = true;
    speaker->AddParam("Int32", "index");
    speaker->SetReturnType("String");
    rtti->RegisterFunction(speaker);

    auto* duration = RED4ext::CGlobalFunction::Create("NativeRadioFramework.NRF_StationTrackDuration", "NRF_StationTrackDuration",
                                                      &NRF_StationTrackDuration);
    duration->flags.isNative = true;
    duration->AddParam("Int32", "index");
    duration->AddParam("Int32", "track");
    duration->SetReturnType("Float");
    rtti->RegisterFunction(duration);

    auto* wwise = RED4ext::CGlobalFunction::Create("NativeRadioFramework.NRF_StationTrackWwiseId", "NRF_StationTrackWwiseId",
                                                   &NRF_StationTrackWwiseId);
    wwise->flags.isNative = true;
    wwise->AddParam("Int32", "index");
    wwise->AddParam("Int32", "track");
    wwise->SetReturnType("Uint32");
    rtti->RegisterFunction(wwise);
}
} // namespace

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"NativeRadioFramework";
    aInfo->author = L"Spuddeh";
    aInfo->version = RED4EXT_V1_SEMVER(0, 1, 0);
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
