// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: The engine's own station clock, handed to AudioXL as each track's start offset.
// File Version: 0.3.0
// Credits: AudioXL by DigitalVixen.
// ======================================================================================
//
// **The engine works out where a vanilla station is in its song and seeks there; on the custom-sound
// path it hands the renderer 0.** So a custom station tuned back to would restart its track. Every
// station object carries a clock (+0x14c) that counts seconds since its current slot began, whether
// or not anyone is listening, on engine time rather than sim time. This reads that clock a few times
// a second for every custom station, asks the engine which track the station is on, and arms that
// track's row in AudioXL with the clock as the start of its next voice (`PlayFrom`). The engine's
// next post of the row, from a tune-in or a receiver toggle, starts where the station is.
//
// **This runs from the plugin's own game-state update, not from a script timer.** A script delay
// callback stops with sim time, and the station selector on foot stops sim time while it is open,
// so a station picked from an open selector posted with nothing armed and started from 0.
// The game-state update runs whenever the game does.
//
// The walk reads engine memory by offset, so it is wrapped in SEH like the probe it came from: a bad
// read disables the clock and says so, and the game carries on with tracks starting from 0.

#pragma once

#include <RED4ext/RED4ext.hpp>
#include <Windows.h>

#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

namespace radioxl::clock
{

// The global holding the engine root pointer, by RED4ext hash, and the walk from it to the radio
// manager's station array - the same walk GetRadioStationCurrentTrackName makes.
constexpr uint32_t kHashEngineRoot = 2549221846;
constexpr size_t kRootAudioSystem = 0xa8;
constexpr size_t kAudioRadioManager = 0xe0;
constexpr size_t kManagerStations = 0x0;
constexpr size_t kManagerCount = 0xc;

// A station object: its type (0 is a station, 5 a playlist), its clock, and the virtual that
// writes its CName.
constexpr size_t kStationType = 0x148;
constexpr size_t kStationClock = 0x14c;
constexpr size_t kVtblGetName = 0x70;

constexpr uint64_t kPeriodMs = 250;      // how often the clock is read and the row re-armed
constexpr uint64_t kHeartbeatMs = 10000; // how often each station's state is logged regardless

using GetNameFn = uint64_t* (*)(void* aSelf, uint64_t* aOut);

// One custom station as the clock sees it.
struct Watched
{
    std::string name;                 // the station CName
    uint64_t nameHash = 0;            // its CName hash, what the engine's object answers with
    // **The engine names a track by the 32-bit FNV-1a of its localization key**, carried in a
    // CName with the high half zero, never by the CName hash of the key's text. Measured: a
    // station's current track came back as 0x0f78ca8c, the 32-bit hash of its key.
    std::vector<uint64_t> trackKeys;
    std::vector<std::string> rows;    // each track's event row, what AudioXL knows it as
    std::vector<float> durations;     // each track's length in seconds
    int lastTrack = -1;               // the track last seen posted, for logging on change
    uint64_t lastUnmatched = 0;       // a returned key that matched no track, logged once
    bool logged = false;
};

struct State
{
    const RED4ext::v1::Sdk* sdk = nullptr;
    RED4ext::v1::PluginHandle handle = nullptr;
    std::vector<Watched> stations;
    uint64_t lastTick = 0;
    uint64_t lastHeartbeat = 0;
    bool failed = false;
    bool audioXL = true;  // cleared once the AudioXLNative class is found missing
};

inline State g_state;

inline void Log(const std::string& aText)
{
    if (g_state.sdk && g_state.sdk->logger)
    {
        g_state.sdk->logger->Info(g_state.handle, aText.c_str());
    }
}

inline uintptr_t ResolveByHash(uint32_t aHash)
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

template <typename T>
inline T Read(uintptr_t aAddress)
{
    return *reinterpret_cast<T*>(aAddress);
}

// A station's clock by name, or a negative number when the station is not in the manager yet.
// Plain data only: this is the function SEH guards, so nothing in it may need a destructor.
inline float ReadClock(uint64_t aNameHash)
{
    const auto rootSlot = ResolveByHash(kHashEngineRoot);
    if (!rootSlot)
    {
        return -2.0f;
    }
    const auto root = Read<uintptr_t>(rootSlot);
    if (!root)
    {
        return -1.0f;
    }
    const auto audio = Read<uintptr_t>(root + kRootAudioSystem);
    if (!audio)
    {
        return -1.0f;
    }
    const auto manager = Read<uintptr_t>(audio + kAudioRadioManager);
    if (!manager)
    {
        return -1.0f;
    }
    const auto stations = Read<uintptr_t>(manager + kManagerStations);
    const auto count = Read<uint32_t>(manager + kManagerCount);
    if (!stations || count > 256)
    {
        return -1.0f;
    }
    for (uint32_t i = 0; i < count; ++i)
    {
        const auto station = Read<uintptr_t>(stations + i * 8);
        if (!station || Read<int32_t>(station + kStationType) != 0)
        {
            continue;
        }
        const auto vtbl = Read<uintptr_t>(station);
        const auto getName = Read<GetNameFn>(vtbl + kVtblGetName);
        uint64_t name = 0;
        getName(reinterpret_cast<void*>(station), &name);
        if (name == aNameHash)
        {
            return Read<float>(station + kStationClock);
        }
    }
    return -1.0f;
}

inline bool SafeReadClock(uint64_t aNameHash, float* aOut)
{
    __try
    {
        *aOut = ReadClock(aNameHash);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

// The track the engine says a station is on, as its index in the station's own list: the engine
// answers with the track's localization key as a CName, which is what the framework wrote into
// every audioRadioTrack row. -1 when the station has not posted yet or the key matches nothing.
inline int CurrentTrack(Watched& aStation)
{
    RED4ext::CName key;
    RED4ext::CName station(aStation.nameHash);
    if (!RED4ext::ExecuteGlobalFunction("GetRadioStationCurrentTrackName", &key, station))
    {
        return -1;
    }
    if (key.hash == 0)
    {
        return -1;
    }
    for (size_t i = 0; i < aStation.trackKeys.size(); ++i)
    {
        if (aStation.trackKeys[i] == key.hash)
        {
            return static_cast<int>(i);
        }
    }
    if (aStation.lastUnmatched != key.hash)
    {
        aStation.lastUnmatched = key.hash;
        char buf[64];
        std::snprintf(buf, sizeof(buf), "%016llx", static_cast<unsigned long long>(key.hash));
        Log(aStation.name + ": the engine names track " + buf + ", which is none of its tracks");
    }
    return -1;
}

// Arms a row's next voice to start at `aSeconds`. AudioXL consumes the value on the next post, so it
// is written every period while the station is on that row.
inline bool Arm(const std::string& aRow, float aSeconds)
{
    if (!g_state.audioXL)
    {
        return false;
    }
    auto* cls = RED4ext::CRTTISystem::Get()->GetClass("AudioXLNative");
    if (!cls)
    {
        g_state.audioXL = false;
        Log("AudioXL is not installed - tracks start from 0 on every tune-in");
        return false;
    }
    // A static native takes no instance, so the call goes straight to the function rather than
    // through the game-system lookup the class-context helper makes.
    auto* fn = cls->GetFunction(RED4ext::CName("PlayFrom"));
    if (!fn)
    {
        g_state.audioXL = false;
        Log("this AudioXL has no PlayFrom - it is older than 0.3.0, tracks start from 0 on every tune-in");
        return false;
    }
    bool ok = false;
    RED4ext::CName row(aRow.c_str());
    float seconds = aSeconds;
    RED4ext::StackArgs_t args;
    args.emplace_back(nullptr, &row);
    args.emplace_back(nullptr, &seconds);
    if (!RED4ext::ExecuteFunction(static_cast<void*>(nullptr), fn, &ok, args))
    {
        return false;
    }
    return ok;
}

inline void Tick()
{
    const uint64_t now = GetTickCount64();
    if (now - g_state.lastTick < kPeriodMs)
    {
        return;
    }
    g_state.lastTick = now;
    const bool heartbeat = now - g_state.lastHeartbeat >= kHeartbeatMs;
    if (heartbeat)
    {
        g_state.lastHeartbeat = now;
    }

    for (auto& station : g_state.stations)
    {
        float clock = -1.0f;
        if (!SafeReadClock(station.nameHash, &clock))
        {
            g_state.failed = true;
            Log("a read of the station clock faulted - offsets are not this build's. Tracks start "
                "from 0 on every tune-in.");
            return;
        }
        if (clock < 0.0f)
        {
            continue;  // no session, or the station is not constructed yet
        }
        const int track = CurrentTrack(station);
        if (track != station.lastTrack)
        {
            station.lastTrack = track;
            if (track >= 0)
            {
                char buf[32];
                std::snprintf(buf, sizeof(buf), "%.2f", clock);
                Log(station.name + " is on track " + std::to_string(track) + " (" + station.rows[track] +
                    "), clock " + buf + " s");
            }
        }
        if (track < 0)
        {
            continue;
        }
        // A clock past the track's end is a slot the engine has not moved off yet; a start there
        // would be refused, so the row is left to start from 0.
        const float duration = station.durations[track];
        const float at = (duration > 0.0f && clock >= duration) ? 0.0f : clock;
        const bool armed = Arm(station.rows[track], at);
        if (heartbeat)
        {
            char buf[64];
            std::snprintf(buf, sizeof(buf), "clock %.2f s, armed %.2f s %s", clock, at, armed ? "ok" : "REFUSED");
            Log(station.name + " track " + std::to_string(track) + ": " + buf);
        }
    }
}

inline bool OnUpdate(RED4ext::CGameApplication*)
{
    if (!g_state.failed && !g_state.stations.empty())
    {
        Tick();
    }
    return false;
}

// Called once from Main after the manifests are read. `aStations` is what the plugin registered.
template <typename StationT, typename EventFn, typename KeyFn>
inline void Start(const RED4ext::v1::Sdk* aSdk, RED4ext::v1::PluginHandle aHandle,
                  const std::vector<StationT>& aStations, EventFn aEvent, KeyFn aKey)
{
    g_state.sdk = aSdk;
    g_state.handle = aHandle;
    for (const auto& s : aStations)
    {
        Watched w;
        w.name = s.name;
        w.nameHash = RED4ext::CName(s.name.c_str()).hash;
        for (size_t i = 0; i < s.tracks.size(); ++i)
        {
            w.trackKeys.push_back(aKey(s, i));
            w.rows.push_back(aEvent(s, i));
            w.durations.push_back(s.tracks[i].duration);
        }
        g_state.stations.push_back(std::move(w));
    }
    if (g_state.stations.empty())
    {
        return;
    }
    static RED4ext::v1::GameState state{
        .OnEnter = nullptr,
        .OnUpdate = OnUpdate,
        .OnExit = nullptr,
    };
    aSdk->gameStates->Add(aHandle, RED4ext::EGameStateType::Running, &state);
    Log("station clock: " + std::to_string(g_state.stations.size()) +
        " station(s) will resume from the engine's own clock");
}

} // namespace radioxl::clock
