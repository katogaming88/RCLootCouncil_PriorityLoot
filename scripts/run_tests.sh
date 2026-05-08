#!/bin/sh
# scripts/run_tests.sh
#
# Run busted from the repo root with LUA_PATH set so spec.wow_mocks resolves.
# Required because LuaRocks .bat shims don't work cleanly in MSYS2 / Git Bash
# (lessons.md 2026-04-20).  On Linux/macOS this is a thin wrapper around
# `busted`; extra args forward to busted.

set -eu

cd "$(dirname "$0")/.."

# LUA_PATH must include the repo root so `require "spec.wow_mocks"` works,
# plus the default LuaRocks search paths.
export LUA_PATH="./?.lua;./?/init.lua;./spec/?.lua;${LUA_PATH:-;;}"

exec busted "$@"
