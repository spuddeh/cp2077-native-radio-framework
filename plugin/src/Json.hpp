// ======================================================================================
// Mod Name: Native Radio Framework
// Author: Spuddeh
// Description: A strict JSON reader that reports the line and column of the first fault.
// File Version: 0.2.0
// ======================================================================================
//
// A station manifest is the one file a station author writes by hand, so it is the one input that
// will be malformed. This reader accepts JSON as RFC 8259 defines it, plus a leading byte-order
// mark, and refuses everything else with the line and column of the first fault and a sentence
// saying what was expected. No dependency, no exceptions, no allocation beyond the tree returned.

#pragma once

#include <cstdint>
#include <cstdlib>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace nrf
{
struct JsonValue
{
    enum class Kind
    {
        Null,
        Bool,
        Number,
        String,
        Array,
        Object
    };

    Kind kind = Kind::Null;
    bool boolean = false;
    double number = 0.0;
    std::string string;
    std::vector<JsonValue> array;
    std::vector<std::pair<std::string, JsonValue>> object;  // in file order, so a walk is stable
    int line = 0;                                            // the line the value starts on, 1-based

    bool Is(Kind aKind) const { return kind == aKind; }

    // The member named aKey, or null. Keys are unique: the reader refuses a duplicate.
    const JsonValue* Find(std::string_view aKey) const
    {
        for (const auto& [key, value] : object)
        {
            if (key == aKey)
            {
                return &value;
            }
        }
        return nullptr;
    }

    static const char* KindName(Kind aKind)
    {
        switch (aKind)
        {
        case Kind::Null: return "null";
        case Kind::Bool: return "true/false";
        case Kind::Number: return "a number";
        case Kind::String: return "a string";
        case Kind::Array: return "an array [...]";
        case Kind::Object: return "an object {...}";
        }
        return "?";
    }
};

struct JsonError
{
    int line = 0;    // 1-based
    int column = 0;  // 1-based, in bytes
    std::string what;
};

class JsonReader
{
public:
    static bool Parse(std::string_view aText, JsonValue& aOut, JsonError& aError)
    {
        JsonReader reader(aText);
        if (aText.size() >= 3 && static_cast<uint8_t>(aText[0]) == 0xEF &&
            static_cast<uint8_t>(aText[1]) == 0xBB && static_cast<uint8_t>(aText[2]) == 0xBF)
        {
            reader.m_pos = 3;
        }
        reader.SkipWhitespace();
        if (reader.AtEnd())
        {
            return reader.Fail("the file is empty", aError);
        }
        if (!reader.ReadValue(aOut, 0))
        {
            return reader.Fail(reader.m_what, aError);
        }
        reader.SkipWhitespace();
        if (!reader.AtEnd())
        {
            return reader.Fail("text after the closing bracket", aError);
        }
        return true;
    }

private:
    static constexpr int kMaxDepth = 32;

    explicit JsonReader(std::string_view aText) : m_text(aText) {}

    std::string_view m_text;
    size_t m_pos = 0;
    size_t m_line = 1;
    size_t m_lineStart = 0;  // offset of the first byte of the current line
    std::string m_what;

    bool AtEnd() const { return m_pos >= m_text.size(); }
    char Peek() const { return AtEnd() ? '\0' : m_text[m_pos]; }
    int Line() const { return static_cast<int>(m_line); }
    int Column() const { return static_cast<int>(m_pos - m_lineStart + 1); }

    bool Fail(const std::string& aWhat, JsonError& aError) const
    {
        aError.line = Line();
        aError.column = Column();
        aError.what = aWhat;
        return false;
    }

    // Records the first fault only; a later one is a consequence of it.
    bool Fault(std::string aWhat)
    {
        if (m_what.empty())
        {
            m_what = std::move(aWhat);
        }
        return false;
    }

    void SkipWhitespace()
    {
        while (!AtEnd())
        {
            const char c = m_text[m_pos];
            if (c == '\n')
            {
                ++m_pos;
                ++m_line;
                m_lineStart = m_pos;
            }
            else if (c == ' ' || c == '\t' || c == '\r')
            {
                ++m_pos;
            }
            else
            {
                break;
            }
        }
    }

    std::string Describe() const
    {
        if (AtEnd())
        {
            return "the end of the file";
        }
        const unsigned char c = static_cast<unsigned char>(m_text[m_pos]);
        if (c == '/')
        {
            return "'/' (a comment is not JSON)";
        }
        if (c == '\'')
        {
            return "a single quote (JSON strings use double quotes)";
        }
        if (c < 0x20 || c >= 0x7F)
        {
            return "a byte that is not JSON";
        }
        return std::string("'") + static_cast<char>(c) + "'";
    }

    bool ReadValue(JsonValue& aOut, int aDepth)
    {
        if (aDepth > kMaxDepth)
        {
            return Fault("nesting deeper than " + std::to_string(kMaxDepth) + " levels");
        }
        aOut.line = Line();
        switch (Peek())
        {
        case '{': return ReadObject(aOut, aDepth);
        case '[': return ReadArray(aOut, aDepth);
        case '"':
            aOut.kind = JsonValue::Kind::String;
            return ReadString(aOut.string);
        case 't': return ReadLiteral("true", aOut, JsonValue::Kind::Bool, true);
        case 'f': return ReadLiteral("false", aOut, JsonValue::Kind::Bool, false);
        case 'n': return ReadLiteral("null", aOut, JsonValue::Kind::Null, false);
        default: break;
        }
        const char c = Peek();
        if (c == '-' || (c >= '0' && c <= '9'))
        {
            return ReadNumber(aOut);
        }
        return Fault("expected a value, found " + Describe());
    }

    bool ReadLiteral(std::string_view aWord, JsonValue& aOut, JsonValue::Kind aKind, bool aBool)
    {
        if (m_text.substr(m_pos, aWord.size()) != aWord)
        {
            return Fault("expected a value, found " + Describe());
        }
        m_pos += aWord.size();
        aOut.kind = aKind;
        aOut.boolean = aBool;
        return true;
    }

    // The JSON number grammar exactly: -?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?
    bool ReadNumber(JsonValue& aOut)
    {
        const size_t start = m_pos;
        auto digit = [this]() { return !AtEnd() && m_text[m_pos] >= '0' && m_text[m_pos] <= '9'; };
        if (Peek() == '-')
        {
            ++m_pos;
        }
        if (Peek() == '0')
        {
            ++m_pos;
            if (digit())
            {
                return Fault("a number may not start with 0");
            }
        }
        else if (digit())
        {
            while (digit())
            {
                ++m_pos;
            }
        }
        else
        {
            return Fault("expected a digit after '-'");
        }
        if (Peek() == '.')
        {
            ++m_pos;
            if (!digit())
            {
                return Fault("expected a digit after '.'");
            }
            while (digit())
            {
                ++m_pos;
            }
        }
        if (Peek() == 'e' || Peek() == 'E')
        {
            ++m_pos;
            if (Peek() == '+' || Peek() == '-')
            {
                ++m_pos;
            }
            if (!digit())
            {
                return Fault("expected a digit in the exponent");
            }
            while (digit())
            {
                ++m_pos;
            }
        }
        const std::string span(m_text.substr(start, m_pos - start));
        aOut.kind = JsonValue::Kind::Number;
        aOut.number = std::strtod(span.c_str(), nullptr);
        return true;
    }

    static bool Hex4(std::string_view aText, unsigned& aOut)
    {
        if (aText.size() < 4)
        {
            return false;
        }
        aOut = 0;
        for (int i = 0; i < 4; ++i)
        {
            const char c = aText[i];
            unsigned v;
            if (c >= '0' && c <= '9')
                v = c - '0';
            else if (c >= 'a' && c <= 'f')
                v = 10 + c - 'a';
            else if (c >= 'A' && c <= 'F')
                v = 10 + c - 'A';
            else
                return false;
            aOut = (aOut << 4) | v;
        }
        return true;
    }

    static void AppendUtf8(std::string& aOut, unsigned aCode)
    {
        if (aCode < 0x80)
        {
            aOut += static_cast<char>(aCode);
        }
        else if (aCode < 0x800)
        {
            aOut += static_cast<char>(0xC0 | (aCode >> 6));
            aOut += static_cast<char>(0x80 | (aCode & 0x3F));
        }
        else if (aCode < 0x10000)
        {
            aOut += static_cast<char>(0xE0 | (aCode >> 12));
            aOut += static_cast<char>(0x80 | ((aCode >> 6) & 0x3F));
            aOut += static_cast<char>(0x80 | (aCode & 0x3F));
        }
        else
        {
            aOut += static_cast<char>(0xF0 | (aCode >> 18));
            aOut += static_cast<char>(0x80 | ((aCode >> 12) & 0x3F));
            aOut += static_cast<char>(0x80 | ((aCode >> 6) & 0x3F));
            aOut += static_cast<char>(0x80 | (aCode & 0x3F));
        }
    }

    // Called on the opening quote. Bytes outside the escapes are kept as they are, so a UTF-8 title
    // survives untouched; a \u escape becomes UTF-8, with a surrogate pair joined.
    bool ReadString(std::string& aOut)
    {
        ++m_pos;
        while (!AtEnd())
        {
            const char c = m_text[m_pos];
            if (c == '"')
            {
                ++m_pos;
                return true;
            }
            if (c == '\n')
            {
                return Fault("a string runs past the end of its line (missing closing quote?)");
            }
            if (static_cast<unsigned char>(c) < 0x20)
            {
                return Fault("a control character inside a string");
            }
            if (c != '\\')
            {
                aOut += c;
                ++m_pos;
                continue;
            }
            ++m_pos;
            if (AtEnd())
            {
                return Fault("the file ends inside a string");
            }
            const char e = m_text[m_pos++];
            switch (e)
            {
            case '"': aOut += '"'; break;
            case '\\': aOut += '\\'; break;
            case '/': aOut += '/'; break;
            case 'b': aOut += '\b'; break;
            case 'f': aOut += '\f'; break;
            case 'n': aOut += '\n'; break;
            case 'r': aOut += '\r'; break;
            case 't': aOut += '\t'; break;
            case 'u':
            {
                unsigned code = 0;
                if (!Hex4(m_text.substr(m_pos), code))
                {
                    return Fault("\\u needs four hex digits");
                }
                m_pos += 4;
                if (code >= 0xD800 && code <= 0xDBFF)
                {
                    unsigned low = 0;
                    if (m_text.substr(m_pos, 2) != "\\u" || !Hex4(m_text.substr(m_pos + 2), low) ||
                        low < 0xDC00 || low > 0xDFFF)
                    {
                        return Fault("a \\u high surrogate without its low half");
                    }
                    m_pos += 6;
                    code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                }
                else if (code >= 0xDC00 && code <= 0xDFFF)
                {
                    return Fault("a \\u low surrogate on its own");
                }
                AppendUtf8(aOut, code);
                break;
            }
            default:
                m_pos -= 2;  // point at the backslash
                return Fault(std::string("unknown escape \\") + e +
                             " (a backslash in a path is written \\\\)");
            }
        }
        return Fault("the file ends inside a string");
    }

    bool ReadArray(JsonValue& aOut, int aDepth)
    {
        aOut.kind = JsonValue::Kind::Array;
        ++m_pos;
        SkipWhitespace();
        if (Peek() == ']')
        {
            ++m_pos;
            return true;
        }
        while (true)
        {
            SkipWhitespace();
            if (Peek() == ']')
            {
                return Fault("a trailing comma before ']'");
            }
            JsonValue item;
            if (!ReadValue(item, aDepth + 1))
            {
                return false;
            }
            aOut.array.push_back(std::move(item));
            SkipWhitespace();
            if (Peek() == ',')
            {
                ++m_pos;
                continue;
            }
            if (Peek() == ']')
            {
                ++m_pos;
                return true;
            }
            if (AtEnd())
            {
                return Fault("the file ends inside an array, ']' missing");
            }
            return Fault("expected ',' or ']' after an array item, found " + Describe());
        }
    }

    bool ReadObject(JsonValue& aOut, int aDepth)
    {
        aOut.kind = JsonValue::Kind::Object;
        ++m_pos;
        SkipWhitespace();
        if (Peek() == '}')
        {
            ++m_pos;
            return true;
        }
        while (true)
        {
            SkipWhitespace();
            if (Peek() == '}')
            {
                return Fault("a trailing comma before '}'");
            }
            if (Peek() != '"')
            {
                if (AtEnd())
                {
                    return Fault("the file ends inside an object, '}' missing");
                }
                return Fault("expected a quoted key, found " + Describe());
            }
            const int keyLine = Line();
            const size_t keyPos = m_pos;
            std::string key;
            if (!ReadString(key))
            {
                return false;
            }
            if (const JsonValue* first = aOut.Find(key))
            {
                m_pos = keyPos;  // point at the key
                return Fault("duplicate key \"" + key + "\" (first at line " + std::to_string(first->line) + ")");
            }
            SkipWhitespace();
            if (Peek() != ':')
            {
                return Fault("expected ':' after key \"" + key + "\", found " + Describe());
            }
            ++m_pos;
            SkipWhitespace();
            JsonValue value;
            if (!ReadValue(value, aDepth + 1))
            {
                return false;
            }
            value.line = keyLine;  // a member is reported at its key, which is where the author looks
            aOut.object.emplace_back(std::move(key), std::move(value));
            SkipWhitespace();
            if (Peek() == ',')
            {
                ++m_pos;
                continue;
            }
            if (Peek() == '}')
            {
                ++m_pos;
                return true;
            }
            if (AtEnd())
            {
                return Fault("the file ends inside an object, '}' missing");
            }
            return Fault("expected ',' or '}' after a value, found " + Describe());
        }
    }
};

inline bool ParseJson(std::string_view aText, JsonValue& aOut, JsonError& aError)
{
    return JsonReader::Parse(aText, aOut, aError);
}
} // namespace nrf
