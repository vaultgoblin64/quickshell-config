# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Documentation Lookup

**Always use Context7 MCP for up-to-date documentation:**
```
# Resolve library ID first
mcp__context7__resolve-library-id("quickshell")

# Then fetch docs with topic
mcp__context7__get-library-docs("/websites/quickshell_v0_2_1", topic: "NotificationServer")
```

Relevant Context7 library IDs:
- Quickshell: `/websites/quickshell_v0_2_1` (v0.2.1 docs)
- Quickshell master: `/websites/quickshell_master`
- Caelestia Shell (reference): `/caelestia-dots/shell`

## Project Overview

This is a Quickshell configuration for Hyprland (Wayland compositor). Quickshell is a QML-based shell framework for building desktop components like status bars, notification daemons, and control panels.

## Running and Testing

```bash
# Start/reload Quickshell
qs

# Start with specific config path
qs -p /path/to/config

# Kill and restart
killall quickshell; qs &

# Test notifications (requires libnotify)
notify-send "Title" "Body"
notify-send -u critical "Critical" "Message"  # urgency levels: low, normal, critical
notify-send -a "appname" -i /path/to/icon.png "Title" "Body"
```

## Architecture

### File Structure
- `shell.qml` - Entry point, loads ShellRoot with Bar component
- `Bar.qml` - Main implementation (~1800 lines) containing all components

### Bar.qml Structure

**Root Scope** contains:
- Shared state properties (audio, network, bluetooth, battery, system info)
- NotificationServer + ListModels for notification handling
- Helper functions (removeActiveNotification, focusAppWorkspace)

**Main Components:**
1. **Top Bar** (`PanelWindow` via `Variants` for multi-monitor)
   - Left: Clock
   - Center: Workspace indicators (Hyprland integration)
   - Right: System warnings, notification bell, volume/network/bluetooth/battery icons

2. **Control Center** (`PopupWindow` inside PanelWindow)
   - Volume slider with mute toggle
   - Network toggle + settings link
   - Bluetooth toggle + settings link
   - System info (CPU, Temp, RAM)
   - Battery status + power profile selector
   - Shutdown button

3. **Notification Center** (`PopupWindow` inside PanelWindow)
   - Header with "Clear all" button
   - ListView of notification history
   - Click to focus app workspace

4. **Notification Popups** (separate `PanelWindow` with `WlrLayershell.layer: WlrLayer.Overlay`)
   - Stacked notifications (max 5)
   - Auto-expire via Timer (except critical)
   - App icons via `Quickshell.iconPath()`

### Key Patterns

**System Data Collection:**
- Uses `Process` + `StdioCollector` for shell commands (wpctl, nmcli, bluetoothctl, etc.)
- Timers trigger periodic updates (1-60 seconds depending on data type)

**Popup Positioning:**
- Control Center/Notification Center: `PopupWindow` with `anchor.window: panel`
- Notification Popups: Separate `PanelWindow` with `WlrLayershell.layer: WlrLayer.Overlay` and `anchors { right: true; top: true }`

**Click-Outside-to-Close:**
- Uses `HyprlandFocusGrab` component

**Notification Handling:**
- Copy notification data to ListModel (don't store object references)
- Use `notification.tracked = true` to prevent auto-destruction
- Timer-based expiration instead of `Qt.createQmlObject()` for stability

## Important Quickshell APIs

```qml
// Icon resolution
Quickshell.iconPath("firefox")  // Returns path to icon

// Hyprland commands
HyprlandIpc.dispatch("workspace 2")
HyprlandIpc.dispatch("focuswindow class:kitty")

// Process execution
Process {
    command: ["sh", "-c", "your command"]
    stdout: StdioCollector { onStreamFinished: result = this.text.trim() }
}

// Detached process
Quickshell.execDetached(["kitty", "nmtui"])
```

## Configuration

User-configurable properties at the top of `Bar.qml`:
```qml
property string terminalApp: "kitty"           // Your terminal emulator
property string networkManager: "nmtui"        // nm-connection-editor, iwctl
property string bluetoothManager: "bluetui"    // blueman-manager, bluetoothctl
```

## Styling

- Background: `Qt.rgba(20/255, 20/255, 25/255, 0.85)` (dark with transparency)
- Accent: `#3b82f6` (blue)
- Warning: `#ef4444` (red)
- Success: `#22c55e` (green)
- Font: "JetBrains Mono Nerd Font" for icons
- Border radius: 10px (bar), 6-8px (buttons/cards)
