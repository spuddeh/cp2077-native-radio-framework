// ======================================================================================
// Mod Name: RadioXL
// Author: Spuddeh
// Description: Tests for the JSON reader and the manifest checks - every fault names its line.
// File Version: 0.2.0
// ======================================================================================
//
// Built as RadioXLManifestTests by the plugin's CMake and run by ctest. Exit code is the failure count.

#include "../src/Manifest.hpp"

#include <cstdio>
#include <string>
#include <vector>

namespace
{
int g_failures = 0;

void Check(bool aCondition, const char* aWhat, const std::string& aDetail = {})
{
    if (!aCondition)
    {
        ++g_failures;
        std::printf("FAIL  %s%s%s\n", aWhat, aDetail.empty() ? "" : " - ", aDetail.c_str());
    }
}

// The manifest read, and every line logged, for one text.
struct Read
{
    bool ok = false;
    radioxl::Station station;
    std::vector<std::string> log;

    explicit Read(const std::string& aText)
    {
        ok = radioxl::ReadManifest(aText, "Mod/station.json", station, [this](const std::string& aLine) { log.push_back(aLine); });
    }

    bool Logged(const std::string& aPrefix) const
    {
        for (const auto& line : log)
        {
            if (line.rfind(aPrefix, 0) == 0)
            {
                return true;
            }
        }
        return false;
    }

    std::string Joined() const
    {
        std::string out;
        for (const auto& line : log)
        {
            out += "\n    " + line;
        }
        return out;
    }
};

// Expects the read to fail and the first logged line to start with aPrefix.
void ExpectFault(const char* aName, const std::string& aText, const std::string& aPrefix)
{
    const Read r(aText);
    Check(!r.ok, aName, "expected the manifest to be refused");
    Check(!r.log.empty() && r.log.front().rfind(aPrefix, 0) == 0, aName,
          "expected first log line to start with '" + aPrefix + "', got" + r.Joined());
}

const char* kGood = R"json({
  "name": "radio_station_20_tool",
  "displayName": "104.9 Tool FM",
  "icon": "tool_fm",
  "atlas": "toolfm\\gui\\tool_fm.inkatlas",
  "speaker": "Stanley",
  "tracks": [
    {
      "file": "audio/Tool - Vicarious.mp3",
      "title": "Tool - Vicarious"
    },
    { "file": "audio/Tool - 10.000 Days (Wings Pt 2).mp3", "title": "Tool - 10,000 Days (Wings Pt. 2)" }
  ]
})json";

void TestGood()
{
    const Read r(kGood);
    Check(r.ok, "good manifest reads", r.Joined());
    Check(r.log.empty(), "good manifest logs nothing", r.Joined());
    Check(r.station.name == "radio_station_20_tool", "name");
    Check(r.station.displayName == "104.9 Tool FM", "displayName");
    Check(r.station.icon == "tool_fm", "icon");
    Check(r.station.atlas == "toolfm\\gui\\tool_fm.inkatlas", "atlas keeps its backslashes", r.station.atlas);
    Check(r.station.speaker == "Stanley", "speaker");
    Check(r.station.gain == radioxl::kDefaultGain, "gain defaults");
    Check(!r.station.shuffle, "shuffle defaults to off");
    Check(r.station.tracks.size() == 2, "two tracks");
    Check(r.station.tracks[1].title == "Tool - 10,000 Days (Wings Pt. 2)", "second title");
}

void TestShuffle()
{
    const std::string on = std::string(kGood).replace(std::string(kGood).find("\"speaker\""), 0, "\"shuffle\": true,\n  ");
    const Read r(on);
    Check(r.ok, "shuffle true reads", r.Joined());
    Check(r.station.shuffle, "shuffle true is read");
    const std::string off = std::string(kGood).replace(std::string(kGood).find("\"speaker\""), 0, "\"shuffle\": false,\n  ");
    Check(!Read(off).station.shuffle, "shuffle false is read");
    ExpectFault("shuffle as a string is refused",
                std::string(kGood).replace(std::string(kGood).find("\"speaker\""), 0, "\"shuffle\": \"yes\",\n  "),
                "Mod/station.json:");
}

void TestTolerated()
{
    // CRLF, a byte-order mark, a forward-slash atlas, a gain, and \u escapes with a surrogate pair.
    const std::string text = "\xEF\xBB\xBF{\r\n"
                             "  \"name\": \"x\",\r\n"
                             "  \"atlas\": \"mod/gui/a.inkatlas\", \"icon\": \"p\",\r\n"
                             "  \"gain\": 0.5,\r\n"
                             "  \"tracks\": [ { \"file\": \"a.mp3\", \"title\": \"caf\\u00e9 \\ud83c\\udfb5 \\\"quoted\\\" }]{\" } ]\r\n"
                             "}\r\n";
    const Read r(text);
    Check(r.ok, "BOM and CRLF read", r.Joined());
    Check(r.station.atlas == "mod\\gui\\a.inkatlas", "atlas forward slashes become backslashes", r.station.atlas);
    Check(r.station.gain == 0.5f, "gain read");
    Check(r.station.tracks.size() == 1 && r.station.tracks[0].title == "caf\xC3\xA9 \xF0\x9F\x8E\xB5 \"quoted\" }]{",
          "escapes and brackets inside a title", r.station.tracks.empty() ? "" : r.station.tracks[0].title);
}

void TestTitleThatFooledTheScanner()
{
    // A title carrying the word "file" in quotes, and a track object whose "name" precedes the
    // station's own: the two shapes the substring scanner read wrongly.
    const std::string text = R"json({
  "tracks": [ { "title": "the \"file\" song", "file": "a.mp3" } ],
  "name": "x"
})json";
    const Read r(text);
    Check(r.ok, "title containing the word file", r.Joined());
    Check(r.station.tracks.size() == 1 && r.station.tracks[0].file == "a.mp3", "file read past the decoy title");
    Check(r.station.name == "x", "station name found after the tracks array");
}

void TestSyntaxFaults()
{
    ExpectFault("trailing comma in object", "{\n  \"name\": \"x\",\n  \"tracks\": [],\n}", "Mod/station.json:4:1: a trailing comma before '}'");
    ExpectFault("trailing comma in array", "{\n  \"name\": \"x\",\n  \"tracks\": [ { \"file\": \"a\" }, ]\n}", "Mod/station.json:3:32: a trailing comma before ']'");
    ExpectFault("missing comma", "{\n  \"name\": \"x\"\n  \"tracks\": []\n}", "Mod/station.json:3:3: expected ',' or '}' after a value");
    ExpectFault("unterminated string", "{\n  \"name\": \"x,\n  \"tracks\": []\n}", "Mod/station.json:2:14: a string runs past the end of its line");
    ExpectFault("single quotes", "{\n  'name': 'x'\n}", "Mod/station.json:2:3: expected a quoted key, found a single quote");
    ExpectFault("comment", "{\n  // the name\n  \"name\": \"x\"\n}", "Mod/station.json:2:3: expected a quoted key, found '/' (a comment is not JSON)");
    ExpectFault("bad escape", "{\n  \"atlas\": \"mod\\gui\\a.inkatlas\"\n}", "Mod/station.json:2:16: unknown escape \\g");
    ExpectFault("duplicate key", "{\n  \"name\": \"x\",\n  \"tracks\": [],\n  \"name\": \"y\"\n}", "Mod/station.json:4:3: duplicate key \"name\" (first at line 2)");
    ExpectFault("empty file", "", "Mod/station.json:1:1: the file is empty");
    ExpectFault("text after root", "{ \"name\": \"x\", \"tracks\": [] }\n}", "Mod/station.json:2:1: text after the closing bracket");
    ExpectFault("file ends inside object", "{\n  \"name\": \"x\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n", "Mod/station.json:4:1: the file ends inside an object, '}' missing");
    ExpectFault("root is an array", "[ 1 ]", "Mod/station.json:1: the manifest must be an object");
    ExpectFault("leading zero", "{ \"gain\": 01 }", "Mod/station.json:1:12: a number may not start with 0");
}

void TestSchemaFaults()
{
    ExpectFault("name missing", "{\n  \"tracks\": [ { \"file\": \"a\" } ]\n}", "Mod/station.json:1: \"name\" is missing");
    ExpectFault("name not a string", "{\n  \"name\": 5,\n  \"tracks\": [ { \"file\": \"a\" } ]\n}", "Mod/station.json:2: \"name\" must be a string, not a number");
    ExpectFault("name with a space", "{\n  \"name\": \"my station\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n}", "Mod/station.json:2: \"name\" must be letters, digits and underscores only");
    ExpectFault("tracks missing", "{\n  \"name\": \"x\"\n}", "Mod/station.json:1: \"tracks\" is missing");
    ExpectFault("tracks empty", "{\n  \"name\": \"x\",\n  \"tracks\": []\n}", "Mod/station.json:3: \"tracks\" is empty");
    ExpectFault("tracks not an array", "{\n  \"name\": \"x\",\n  \"tracks\": { \"file\": \"a\" }\n}", "Mod/station.json:3: \"tracks\" must be an array [...], not an object {...}");
    ExpectFault("track not an object", "{\n  \"name\": \"x\",\n  \"tracks\": [ \"a.mp3\" ]\n}", "Mod/station.json:3: each track must be an object");
    ExpectFault("track without file", "{\n  \"name\": \"x\",\n  \"tracks\": [\n    { \"title\": \"t\" }\n  ]\n}", "Mod/station.json:4: \"file\" is missing");
    ExpectFault("track file empty", "{\n  \"name\": \"x\",\n  \"tracks\": [\n    { \"file\": \"\" }\n  ]\n}", "Mod/station.json:4: \"file\" is empty");
    ExpectFault("speaker unknown", "{\n  \"name\": \"x\",\n  \"speaker\": \"Stanly\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n}", "Mod/station.json:3: \"speaker\" must be one of None, Stanley, MaximumMike, Ash, Kurtz, PoliceDispatch: \"Stanly\"");
    ExpectFault("gain as a string", "{\n  \"name\": \"x\",\n  \"gain\": \"0.5\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n}", "Mod/station.json:3: \"gain\" must be a number, not a string");
    ExpectFault("icon without atlas", "{\n  \"name\": \"x\",\n  \"icon\": \"p\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n}", "Mod/station.json:3: \"icon\" names an atlas part");
}

void TestWarnings()
{
    const std::string text = R"json({
  "name": "x",
  "dispalyName": "typo",
  "gain": 1.5,
  "atlas": "m\\a.inkatlas",
  "tracks": [ { "file": "a", "titel": "typo" } ]
})json";
    const Read r(text);
    Check(r.ok, "warnings do not refuse the manifest", r.Joined());
    Check(r.Logged("Mod/station.json:3: unknown manifest key \"dispalyName\" - ignored"), "unknown top-level key named", r.Joined());
    Check(r.Logged("Mod/station.json:4: \"gain\" is 0 to 1 - clamped"), "gain out of range named", r.Joined());
    Check(r.station.gain == 1.0f, "gain clamped");
    Check(r.Logged("Mod/station.json:5: \"atlas\" without \"icon\" does nothing - ignored"), "atlas without icon named", r.Joined());
    Check(r.Logged("Mod/station.json:6: unknown track key \"titel\" - ignored"), "unknown track key named", r.Joined());
    Check(r.log.size() == 4, "exactly four warnings", r.Joined());
}

void TestEveryFaultIsReported()
{
    // Two faults on two lines: both are named, so the author fixes the file once.
    const Read r("{\n  \"name\": \"bad name\",\n  \"speaker\": \"DJ\",\n  \"tracks\": [ { \"file\": \"a\" } ]\n}");
    Check(!r.ok, "two faults refuse");
    Check(r.log.size() == 2, "both faults logged", r.Joined());
    Check(r.Logged("Mod/station.json:2:"), "first at line 2", r.Joined());
    Check(r.Logged("Mod/station.json:3:"), "second at line 3", r.Joined());
}
} // namespace

int main()
{
    TestGood();
    TestShuffle();
    TestTolerated();
    TestTitleThatFooledTheScanner();
    TestSyntaxFaults();
    TestSchemaFaults();
    TestWarnings();
    TestEveryFaultIsReported();
    if (g_failures == 0)
    {
        std::printf("ok\n");
    }
    return g_failures;
}
