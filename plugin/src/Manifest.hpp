// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: A station manifest read whole, then checked field by field, every fault by line.
// File Version: 0.2.0
// ======================================================================================
//
// A manifest with a fault is skipped whole rather than half-loaded: a station that loads with one
// field missing looks like a bug somewhere else, and the log line saying which line of which file
// is the whole of what a station author needs.

#pragma once

#include "Json.hpp"

#include <algorithm>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

namespace radioxl
{
// A track is an audio FILE and a title. Nothing else is written by hand: the length is read from
// the file's own headers at load, and AudioXL registers the file and supplies the Wwise id. A
// manifest that carried a duration would be a second place for it to be wrong.
struct Track
{
    std::string file;       // relative to the station's own manifest folder
    std::string title;      // the song title as it is shown, plain text, may be empty
    float duration = 0.0f;  // seconds, from the file's headers - what the station schedules against
};

// The level trim every station gets unless its manifest says otherwise. **A station's level belongs
// on its send, not in its samples**, and the framework's own routing bank puts it there, so the
// default here leaves the audio alone. The correction for the game's own custom-radio object, whose
// send reaches a world device 3 to 7 dB hotter than any vanilla station, is applied in script and
// only on the path that uses that object.
constexpr float kDefaultGain = 1.0f;

struct Station
{
    std::string name;          // the station CName, e.g. radio_station_20_tool
    std::string displayName;   // the label the UI shows, plain text
    std::string icon;          // an inkatlas part name, or empty for the framework's own glyph
    std::string atlas;         // the inkatlas resource holding that part, or empty for the framework's
    std::string speaker;       // audioRadioSpeakerType - the station's DJ
    float gain = kDefaultGain; // level trim applied to every track's samples, 0..1; see RadioXL_StationGain
    std::vector<Track> tracks;
    std::string source;        // which manifest it came from, for logging
    std::string folder;        // the manifest's own directory, which track files are relative to
};

// A depot path uses backslashes. A manifest may write either.
inline std::string DepotPath(std::string aPath)
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

// The five DJs the engine has, and None. The redscript half maps the word to the enum; a word it
// does not know would fall to None silently, so the check is here where the line is known.
constexpr std::string_view kSpeakers[] = {"None", "Stanley", "MaximumMike", "Ash", "Kurtz", "PoliceDispatch"};

// A station name becomes a CName, an event-name prefix and a TweakDB record id, and the last of
// those splits on '.', so the name is held to what every one of them accepts.
inline bool IsStationName(std::string_view aName)
{
    if (aName.empty())
    {
        return false;
    }
    for (const char c : aName)
    {
        const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
        if (!ok)
        {
            return false;
        }
    }
    return true;
}

using ManifestLog = std::function<void(const std::string&)>;

// Reads aText as the manifest at aWhere ("<Mod>/station.json") into aOut. Every line written to
// aLog is `<where>:<line>: <what>`. Returns false when the station must not be registered; a
// warning is logged the same way and does not fail the manifest.
inline bool ReadManifest(std::string_view aText, const std::string& aWhere, Station& aOut, const ManifestLog& aLog)
{
    JsonValue root;
    JsonError error;
    if (!ParseJson(aText, root, error))
    {
        aLog(aWhere + ":" + std::to_string(error.line) + ":" + std::to_string(error.column) + ": " + error.what);
        return false;
    }

    bool ok = true;
    auto at = [&](int aLine, const std::string& aWhat) { aLog(aWhere + ":" + std::to_string(aLine) + ": " + aWhat); };
    auto fail = [&](int aLine, const std::string& aWhat)
    {
        at(aLine, aWhat);
        ok = false;
    };

    if (!root.Is(JsonValue::Kind::Object))
    {
        fail(root.line, "the manifest must be an object, { ... }");
        return false;
    }

    // A member that is present must be the kind the field wants; absent is fine for an optional one.
    auto expect = [&](const JsonValue& aObject, std::string_view aKey, JsonValue::Kind aKind, bool aRequired) -> const JsonValue*
    {
        const JsonValue* value = aObject.Find(aKey);
        if (!value)
        {
            if (aRequired)
            {
                fail(aObject.line, "\"" + std::string(aKey) + "\" is missing");
            }
            return nullptr;
        }
        if (!value->Is(aKind))
        {
            fail(value->line, "\"" + std::string(aKey) + "\" must be " + JsonValue::KindName(aKind) + ", not " +
                                  JsonValue::KindName(value->kind));
            return nullptr;
        }
        return value;
    };

    auto unknownKeys = [&](const JsonValue& aObject, std::initializer_list<std::string_view> aKnown, const char* aWhat)
    {
        for (const auto& [key, value] : aObject.object)
        {
            if (std::find(aKnown.begin(), aKnown.end(), key) == aKnown.end())
            {
                at(value.line, std::string("unknown ") + aWhat + " key \"" + key + "\" - ignored");
            }
        }
    };

    unknownKeys(root, {"name", "displayName", "icon", "atlas", "speaker", "gain", "tracks"}, "manifest");

    if (const JsonValue* name = expect(root, "name", JsonValue::Kind::String, true))
    {
        if (!IsStationName(name->string))
        {
            fail(name->line, "\"name\" must be letters, digits and underscores only: \"" + name->string + "\"");
        }
        aOut.name = name->string;
    }

    if (const JsonValue* displayName = expect(root, "displayName", JsonValue::Kind::String, false))
    {
        aOut.displayName = displayName->string;
    }

    const JsonValue* icon = expect(root, "icon", JsonValue::Kind::String, false);
    const JsonValue* atlas = expect(root, "atlas", JsonValue::Kind::String, false);
    if (icon && !icon->string.empty() && (!atlas || atlas->string.empty()))
    {
        fail(icon->line, "\"icon\" names an atlas part, so \"atlas\" must name the inkatlas holding it");
    }
    if (atlas && !atlas->string.empty() && (!icon || icon->string.empty()))
    {
        at(atlas->line, "\"atlas\" without \"icon\" does nothing - ignored");
    }
    if (icon)
    {
        aOut.icon = icon->string;
    }
    if (atlas)
    {
        aOut.atlas = DepotPath(atlas->string);
    }

    if (const JsonValue* speaker = expect(root, "speaker", JsonValue::Kind::String, false))
    {
        if (std::find(std::begin(kSpeakers), std::end(kSpeakers), speaker->string) == std::end(kSpeakers))
        {
            std::string list;
            for (const auto s : kSpeakers)
            {
                list += (list.empty() ? "" : ", ") + std::string(s);
            }
            fail(speaker->line, "\"speaker\" must be one of " + list + ": \"" + speaker->string + "\"");
        }
        aOut.speaker = speaker->string;
    }

    if (const JsonValue* gain = expect(root, "gain", JsonValue::Kind::Number, false))
    {
        if (gain->number < 0.0 || gain->number > 1.0)
        {
            at(gain->line, "\"gain\" is 0 to 1 - clamped");
        }
        aOut.gain = std::clamp(static_cast<float>(gain->number), 0.0f, 1.0f);
    }

    if (const JsonValue* tracks = expect(root, "tracks", JsonValue::Kind::Array, true))
    {
        if (tracks->array.empty())
        {
            fail(tracks->line, "\"tracks\" is empty - a station needs at least one");
        }
        for (const JsonValue& item : tracks->array)
        {
            if (!item.Is(JsonValue::Kind::Object))
            {
                fail(item.line, "each track must be an object, { \"file\": ... }, not " + std::string(JsonValue::KindName(item.kind)));
                continue;
            }
            unknownKeys(item, {"file", "title"}, "track");
            Track track;
            if (const JsonValue* file = expect(item, "file", JsonValue::Kind::String, true))
            {
                if (file->string.empty())
                {
                    fail(file->line, "\"file\" is empty");
                }
                track.file = file->string;
            }
            if (const JsonValue* title = expect(item, "title", JsonValue::Kind::String, false))
            {
                track.title = title->string;
            }
            aOut.tracks.push_back(std::move(track));
        }
    }

    return ok;
}
} // namespace radioxl
