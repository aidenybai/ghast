# Ghast

A native macOS terminal multiplexer built with SwiftUI and [Ghostty](https://ghostty.org).

Forked from [cmux](https://github.com/manaflow-ai/cmux).

## Features

- **Workspaces** — tabs grouped by working directory, auto-organized as you `cd`
- **Split panes** — horizontal and vertical splits with draggable dividers, resize, equalize, and zoom
- **Tab management** — drag-to-reorder, keyboard shortcuts (Cmd+1-9), split-by-drag
- **Drag & drop** — drop files/folders from Finder to paste shell-escaped paths
- **Ghostty config** — reads your `~/.config/ghostty/config` for keybindings, colors, fonts
- **URL handling** — clickable links open in your default browser
- **Desktop notifications** — terminal programs can send macOS notifications
- **Search** — search terminal output via Ghostty keybindings

## Prerequisites

- macOS 13.0+
- [Zig](https://ziglang.org) toolchain (for building GhosttyKit)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Xcode 15+

## Build

```bash
# Clone with submodules
git clone --recursive https://github.com/MarvinSchwaibold/ghast.git
cd ghast

# Run setup (inits submodule, builds GhosttyKit, generates Xcode project)
./scripts/setup.sh

# Build
xcodebuild -project ghast.xcodeproj -scheme ghast -configuration Release build

# Or open in Xcode
open ghast.xcodeproj
```

## Usage

Ghast respects your Ghostty keybindings. Default shortcuts:

| Action | Shortcut |
|--------|----------|
| New tab | Cmd+T |
| Close tab | Cmd+W |
| New window | Cmd+N |
| Split right | Cmd+D |
| Split down | Cmd+Shift+D |
| Next pane | Cmd+Option+] |
| Previous pane | Cmd+Option+[ |
| Tab 1-9 | Cmd+1-9 |

## Credits

- [Ghostty](https://ghostty.org) by Mitchell Hashimoto — the terminal engine
- [cmux](https://github.com/manaflow-ai/cmux) — the original project this was forked from
