default:
    just --list

bootstrap:
    #!/usr/bin/env sh
    set -eu
    mkdir -p .artifacts
    curl --fail --location --output .artifacts/nvim-linux-x86_64.appimage https://github.com/neovim/neovim/releases/download/v0.12.2/nvim-linux-x86_64.appimage
    chmod +x .artifacts/nvim-linux-x86_64.appimage

lint:
    #!/usr/bin/env sh
    set -eu
    appimage=.artifacts/nvim-linux-x86_64.appimage
    if [ ! -f "$appimage" ]; then
      printf '%s\n' "Neovim AppImage is missing: run 'just bootstrap'" >&2
      exit 1
    fi
    if ! command -v lua-language-server >/dev/null 2>&1; then
      printf '%s\n' "lua-language-server 3.18.2 or newer must be available on PATH" >&2
      exit 1
    fi
    chmod +x "$appimage"
    APPIMAGE_EXTRACT_AND_RUN=1 "$appimage" --headless --clean --noplugin -n -i NONE -u NONE -l scripts/lint.lua

sandbox name="":
    #!/usr/bin/env sh
    set -eu
    repo_root=$(pwd -P)
    appimage="$repo_root/.artifacts/nvim-linux-x86_64.appimage"
    if [ ! -f "$appimage" ]; then
      printf '%s\n' "Neovim AppImage is missing: run 'just bootstrap'" >&2
      exit 1
    fi
    chmod +x "$appimage"
    DIFFREVIEW_SANDBOX_NAME={{ quote(name) }} APPIMAGE_EXTRACT_AND_RUN=1 "$appimage" -n -i NONE -u "$repo_root/sandbox/init.lua"

format:
    stylua lua plugin sandbox scripts tests

format-check:
    stylua --check lua plugin sandbox scripts tests

[private]
run-test category test_name="":
    #!/usr/bin/env sh
    set -eu
    repo_root=$(pwd -P)
    artifacts="$repo_root/.artifacts"
    appimage="$artifacts/nvim-linux-x86_64.appimage"
    if [ ! -f "$appimage" ]; then
      printf '%s\n' "Neovim AppImage is missing: run 'just bootstrap'" >&2
      exit 1
    fi
    chmod +x "$appimage"
    test_root=
    cleanup() {
      if [ -n "$test_root" ]; then rm -rf "$test_root"; fi
    }
    trap cleanup 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    test_root=$(mktemp -d "$artifacts/diff-review-tests.XXXXXX")
    mkdir -p "$test_root/tmp" "$test_root/home" "$test_root/xdg/config" "$test_root/xdg/data" "$test_root/xdg/state" "$test_root/xdg/cache" "$test_root/xdg/runtime"
    chmod 700 "$test_root/xdg/runtime"
    : > "$test_root/nvim.log"
    : > "$test_root/gitconfig-global"
    : > "$test_root/gitconfig-system"
    HOME="$test_root/home" \
      TMPDIR="$test_root/tmp" \
      XDG_CONFIG_HOME="$test_root/xdg/config" \
      XDG_DATA_HOME="$test_root/xdg/data" \
      XDG_STATE_HOME="$test_root/xdg/state" \
      XDG_CACHE_HOME="$test_root/xdg/cache" \
      XDG_RUNTIME_DIR="$test_root/xdg/runtime" \
      NVIM_LOG_FILE="$test_root/nvim.log" \
      GIT_CONFIG_GLOBAL="$test_root/gitconfig-global" \
      GIT_CONFIG_SYSTEM="$test_root/gitconfig-system" \
      APPIMAGE_EXTRACT_AND_RUN=1 \
      "$appimage" --headless --clean --noplugin -n -i NONE -u tests/minimal_init.lua -l tests/run.lua {{ category }} "{{ test_name }}"

test-unit test_name="": (run-test "unit" test_name)

test-integration test_name="": (run-test "integration" test_name)

test-functional test_name="": (run-test "functional" test_name)

test: test-unit test-integration test-functional
