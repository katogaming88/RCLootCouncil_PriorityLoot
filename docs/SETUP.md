# Development Environment Setup

Step-by-step instructions for getting `luacheck` and `busted` running locally so you can lint and test before pushing.

If you only need a high-level summary, see the "Local development setup" section in `CONTRIBUTING.md`. This doc is the full recipe.

## What you need

| Tool | Version | Why |
|---|---|---|
| Lua | 5.1 | WoW runs LuaJIT (Lua 5.1 compatible). Pinning to 5.1 locally avoids version-skew bugs. |
| LuaRocks | any recent (3.x) | Package manager for `luacheck` and `busted`. |
| `luacheck` | latest | Static analyser; CI gate. |
| `busted` | latest | Test runner; CI gate. |

CI uses `leafo/gh-actions-lua@v10` with `luaVersion: "5.1"` plus `leafo/gh-actions-luarocks@v4`. Local setup should match.

---

## Linux (Ubuntu / Debian / Fedora)

### Ubuntu / Debian

```bash
sudo apt-get update
sudo apt-get install -y lua5.1 liblua5.1-0-dev luarocks
```

`apt`'s `luarocks` package may default to a different Lua version than 5.1 (Ubuntu 22.04 ships 5.3 as the default; 24.04 ships 5.4). Always pass `--lua-version=5.1` explicitly when installing rocks:

```bash
sudo luarocks --lua-version=5.1 install luacheck
sudo luarocks --lua-version=5.1 install busted
```

### Fedora

```bash
sudo dnf install lua-5.1 lua-devel luarocks
sudo luarocks --lua-version=5.1 install luacheck
sudo luarocks --lua-version=5.1 install busted
```

### Verify

```bash
lua5.1 -v          # Lua 5.1.5
luarocks --version # /usr/bin/luarocks 3.8.0
luacheck --version # Luacheck: 1.x ; Lua: Lua 5.1
busted --version   # 2.x
```

If `luacheck` or `busted` shows `Lua: Lua 5.3` instead of 5.1, you installed for the wrong version. Reinstall with `--lua-version=5.1`.

---

## macOS

Homebrew's `lua@5.1` formula is keg-only (it does not symlink into the default `PATH`).

```bash
brew install lua@5.1
brew install luarocks

# Wire up the keg-only Lua so /usr/local/bin/lua points at 5.1
brew link --force lua@5.1   # or add `$(brew --prefix lua@5.1)/bin` to PATH

luarocks --lua-version=5.1 install luacheck
luarocks --lua-version=5.1 install busted
```

If `brew link --force` complains about conflicts with another Lua install, use the PATH approach instead:

```bash
echo 'export PATH="$(brew --prefix lua@5.1)/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Verify the same way as on Linux.

---

## Windows (MSYS2 / Git Bash)

This is the trickiest path. Skip `chocolatey`'s `lua` package: its bundled LuaRocks 2.x cannot parse modern dependency specifications, and the Lua `.lib` files are MSVC-format which MinGW cannot link against.

### Step 1: Install Lua 5.1 + LuaRocks via the Win32 legacy bundle

Download the latest `LuaRocks-X.Y.Z-windows-32.zip` (the "legacy" Win32 bundle that includes Lua 5.1) from <https://luarocks.org/wiki/rocks/show?package=luarocks>. Extract to `C:\LuaRocks\`.

The bundle gives you:

- `C:\LuaRocks\lua5.1.exe` (no plain `lua.exe`)
- `C:\LuaRocks\luarocks.bat`
- `C:\LuaRocks\bin\` for installed rock binaries (`luacheck.bat`, `busted.bat`, etc.)

### Step 2: Install MSVC build tools

You need `cl.exe` on `PATH` so LuaRocks can compile rocks that have C dependencies.

1. Install Visual Studio 2022 Build Tools (free).
2. **Always launch a "Developer Command Prompt for VS 2022"** before running `luarocks install`. This sets up `cl.exe` and the right environment variables. Do not run installs from a regular `cmd` or Git Bash window.

### Step 3: Install luacheck and busted

From a Developer Command Prompt for VS 2022:

```cmd
cd C:\LuaRocks
luarocks install luacheck
luarocks install busted
```

This drops `.bat` shims in `C:\LuaRocks\bin\`.

### Step 4: Make Lua, luacheck, and busted runnable from Git Bash / MSYS2

The `.bat` shims that LuaRocks installs **do not work reliably from MSYS2 / Git Bash** (`cmd.exe` invocation, path translation, and exit-code handling all fight each other). The fix is to write thin bash wrappers in `~/bin/` (which is on `PATH` for Git Bash via `/etc/profile.d/env.sh`, even in environments that do not source `~/.bashrc`).

Create `~/bin/lua`:

```bash
#!/usr/bin/env bash
exec /c/LuaRocks/lua5.1.exe "$@"
```

Create `~/bin/luacheck`:

```bash
#!/usr/bin/env bash
LUACHECK_VERSION="1.2.0-1"  # update after `luarocks install luacheck` upgrades
exec /c/LuaRocks/lua5.1.exe \
  -e "package.path = 'C:/LuaRocks/systree/share/lua/5.1/?.lua;C:/LuaRocks/systree/share/lua/5.1/?/init.lua;' .. package.path" \
  -e "package.cpath = 'C:/LuaRocks/systree/lib/lua/5.1/?.dll;' .. package.cpath" \
  /c/LuaRocks/systree/lib/luarocks/rocks-5.1/luacheck/${LUACHECK_VERSION}/bin/luacheck.lua "$@"
```

Create `~/bin/busted`:

```bash
#!/usr/bin/env bash
BUSTED_VERSION="2.2.0-1"  # update after `luarocks install busted` upgrades
exec /c/LuaRocks/lua5.1.exe \
  -e "package.path = 'C:/LuaRocks/systree/share/lua/5.1/?.lua;C:/LuaRocks/systree/share/lua/5.1/?/init.lua;' .. package.path" \
  -e "package.cpath = 'C:/LuaRocks/systree/lib/lua/5.1/?.dll;' .. package.cpath" \
  /c/LuaRocks/systree/lib/luarocks/rocks-5.1/busted/${BUSTED_VERSION}/bin/busted "$@"
```

Make them executable:

```bash
chmod +x ~/bin/lua ~/bin/luacheck ~/bin/busted
```

The version suffixes (`1.2.0-1`, `2.2.0-1`) are the LuaRocks rock versions and **must match what was installed**. Check `ls /c/LuaRocks/systree/lib/luarocks/rocks-5.1/luacheck/` to find the actual version string. After running `luarocks install <pkg>` to upgrade, update the variable at the top of each shim.

### Step 5: Verify

In a fresh Git Bash window:

```bash
lua -v             # Lua 5.1.5  Copyright (C) 1994-2012 Lua.org, PUC-Rio
luacheck --version # Luacheck: 1.2.0
busted --version   # 2.2.0
```

Then from the repo root:

```bash
luacheck .
bash scripts/run_tests.sh
```

Both should exit 0.

---

## Troubleshooting

### `luarocks install` says "lua header not found"

You did not run from a Developer Command Prompt (Windows) or did not install the Lua dev headers (Linux: `liblua5.1-0-dev`).

### `luacheck` or `busted` reports the wrong Lua version

You installed the rock for a different Lua version than you are running. Reinstall:

```bash
sudo luarocks --lua-version=5.1 install --force luacheck busted
```

### `python3` is "not found" on Windows but `python` works

Python.org's Windows installer creates `python.exe`, never `python3.exe`. The Windows Store "App Execution Alias" intercepts `python3` and returns a Store redirect (exit code 49), which scripts mistake for "command failed silently." Fix: Settings → Apps → App execution aliases → disable the `python3.exe` Store alias, then in your Python install directory run `cp python.exe python3.exe`. Re-copy after every Python upgrade.

### `bash scripts/run_tests.sh` fails with `module 'spec.wow_mocks' not found`

Either you ran `busted` directly (without the wrapper that sets `LUA_PATH`) from a directory that is not the repo root, or your `LUA_PATH` is missing the repo's local search paths. Always run via `bash scripts/run_tests.sh` from the repo root.

### Tests pass locally but fail on CI (or vice versa)

Most likely a Lua version mismatch. CI pins `luaVersion: "5.1"`. Confirm `luacheck --version` and `busted --version` locally show `Lua: Lua 5.1`.

### Symlinks created from MSYS2 / Git Bash silently produce file copies

Set `export MSYS=winsymlinks:nativestrict` in your environment before running `ln -s`. Without it, MSYS silently degrades symlinks to file copies on Windows filesystem paths. This affects any setup script that uses `ln -s`.

---

## What CI does (for reference)

`.github/workflows/ci.yml`:

```yaml
- uses: leafo/gh-actions-lua@v10
  with:
    luaVersion: "5.1"
- uses: leafo/gh-actions-luarocks@v4
- run: luarocks install luacheck    # or busted, in the test job
- run: luacheck .                   # or bash scripts/run_tests.sh
```

This is the simplest possible CI for a Lua project; no `apt-get` setup, no version-skew traps. If your local setup matches what CI does, your local `luacheck .` and `bash scripts/run_tests.sh` results are an accurate predictor of the PR's CI outcome.
