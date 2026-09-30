"""Compile the production parser methods with a small packet/UI test harness."""

import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile


def method(source, name):
    start = source.index(f"void ProtocolGame::{name}(")
    brace = source.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


parser_path, sender_path, constants_path, features_path = map(Path, sys.argv[1:])
parser = parser_path.read_text(encoding="utf-8")
sender = sender_path.read_text(encoding="utf-8")
constants = constants_path.read_text(encoding="utf-8")
features = features_path.read_text(encoding="utf-8")
feature_id = int(re.search(r"GameAstraExtendedSpellIds\s*=\s*(\d+)", constants)[1])
assert feature_id == 152, "spell cooldown feature id changed"
assert re.search(r"LastGameFeature\s*=\s*153", constants)
assert re.search(r"ASTRA_CAPABILITY_EXTENDED_SPELL_IDS\s*=\s*1U\s*<<\s*6", sender)
assert "ASTRA_CAPABILITY_EXTENDED_SPELL_IDS;" in sender, "login does not advertise the capability"
assert "disableFeature(Otc::GameAstraExtendedSpellIds)" in sender, "login must reset stale width"
assert not re.search(r"enableFeature\(GameAstraExtendedSpellIds\)", features), "U16 must be negotiated"

harness = r"""
#include <array>
#include <cassert>
#include <cstdint>
#include <initializer_list>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace Otc { enum GameFeature { GameAstraExtendedSpellIds = FEATURE_ID }; }
class InputMessage {
    std::vector<uint8_t> bytes;
    size_t cursor = 0;
public:
    InputMessage(std::initializer_list<uint8_t> data) : bytes(data) {}
    uint8_t getU8() {
        if (cursor >= bytes.size()) throw std::runtime_error("InputMessage eof reached");
        return bytes[cursor++];
    }
    uint16_t getU16() {
        const uint16_t low = getU8();
        return low | (uint16_t(getU8()) << 8);
    }
    uint32_t getU32() {
        const uint32_t low = getU16();
        return low | (uint32_t(getU16()) << 16);
    }
    size_t unread() const { return bytes.size() - cursor; }
};
using InputMessagePtr = std::shared_ptr<InputMessage>;
struct Game {
    bool extended = false;
    bool getFeature(Otc::GameFeature feature) const {
        assert(feature == Otc::GameAstraExtendedSpellIds);
        return extended;
    }
    void enableFeature(Otc::GameFeature feature) { getFeature(feature); extended = true; }
    void disableFeature(Otc::GameFeature feature) { getFeature(feature); extended = false; }
} g_game;
struct Lua {
    std::string event;
    int id = -1, delay = -1, calls = 0;
    void callGlobalField(const char* target, const char* field, int value, int duration) {
        assert(std::string(target) == "g_game");
        event = field; id = value; delay = duration; ++calls;
    }
} g_lua;
class ProtocolGame {
public:
    void parseSpellCooldown(const InputMessagePtr& msg);
    void parseSpellGroupCooldown(const InputMessagePtr& msg);
    void parseFeatures(const InputMessagePtr& msg);
};

PRODUCTION_METHODS

void check(ProtocolGame& protocol, std::initializer_list<uint8_t> packet,
           bool extended, int id, int delay) {
    g_game.extended = extended;
    const auto msg = std::make_shared<InputMessage>(packet);
    assert(msg->getU8() == 0xA4);
    const int calls = g_lua.calls;
    protocol.parseSpellCooldown(msg);
    assert(g_lua.calls == calls + 1);
    assert(g_lua.event == "onSpellCooldown" && g_lua.id == id && g_lua.delay == delay);
    assert(msg->unread() == 0);
}
int main() {
    ProtocolGame protocol;
    check(protocol, {0xA4, 0x2A, 0xE8, 0x03, 0x00, 0x00}, false, 42, 1000);
    check(protocol, {0xA4, 0xFF, 0xE8, 0x03, 0x00, 0x00}, false, 255, 1000);
    check(protocol, {0xA4, 0x2A, 0x00, 0xE8, 0x03, 0x00, 0x00}, true, 42, 1000);
    check(protocol, {0xA4, 0x13, 0x01, 0xE8, 0x03, 0x00, 0x00}, true, 275, 1000);
    check(protocol, {0xA4, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00}, true, 65535, 0);
    check(protocol, {0xA4, 0x13, 0x01, 0x00, 0x00, 0x00, 0x00}, true, 275, 0);

    // Negotiate in-band before the first cooldown, followed by the next real opcode.
    g_game.extended = false;
    auto msg = std::make_shared<InputMessage>(std::initializer_list<uint8_t>{
        0x43, 0x01, 0x00, FEATURE_ID, 0x01,
        0xA4, 0x04, 0x00, 0xE8, 0x03, 0x00, 0x00,
        0xA5, 0x02, 0xD0, 0x07, 0x00, 0x00});
    assert(msg->getU8() == 0x43);
    protocol.parseFeatures(msg);
    assert(g_game.extended && msg->getU8() == 0xA4);
    protocol.parseSpellCooldown(msg);
    assert(g_lua.id == 4 && g_lua.delay == 1000);
    assert(msg->unread() == 6 && msg->getU8() == 0xA5);
    protocol.parseSpellGroupCooldown(msg);
    assert(g_lua.event == "onSpellGroupCooldown" && g_lua.id == 2 && g_lua.delay == 2000);
    assert(msg->unread() == 0);

    // Disable the feature and parse a subsequent legacy packet without stale width.
    msg = std::make_shared<InputMessage>(std::initializer_list<uint8_t>{
        0x01, 0x00, FEATURE_ID, 0x00, 0xA4, 0x2A, 0xE8, 0x03, 0x00, 0x00});
    protocol.parseFeatures(msg);
    assert(!g_game.extended && msg->getU8() == 0xA4);
    protocol.parseSpellCooldown(msg);
    assert(g_lua.id == 42 && g_lua.delay == 1000 && msg->unread() == 0);
    std::cout << "spell cooldown production parser: OK\n";
}
"""

methods = "\n\n".join(method(parser, name) for name in (
    "parseSpellCooldown", "parseSpellGroupCooldown", "parseFeatures"
))
harness = harness.replace("PRODUCTION_METHODS", methods).replace("FEATURE_ID", str(feature_id))
with tempfile.TemporaryDirectory(prefix="astra-spell-cooldown-") as directory:
    source = Path(directory) / "spell_cooldown.cpp"
    executable = Path(directory) / "spell_cooldown"
    source.write_text(harness, encoding="utf-8")
    compiler = shlex.split(os.environ.get("CXX", "c++"))
    subprocess.run(compiler + ["-std=c++17", "-Wall", "-Wextra", "-pedantic", str(source), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
