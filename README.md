# Quickshell Config

A custom Quickshell configuration for Hyprland with a modern top bar, control center, and notification system.

## Features

- **Top Bar** - Clock, workspaces, system tray, volume/network/bluetooth indicators
- **Control Center** - Quick toggles and sliders for volume, network, bluetooth
- **Notification Daemon** - Popup notifications with history center
- **Hyprland Integration** - Workspace switching, window focus, IPC communication

## Requirements

- [Quickshell](https://quickshell.outfoxxed.me/)
- Hyprland
- JetBrains Mono Nerd Font
- `wpctl` (WirePlumber) for audio control
- `libnotify` for notification testing (`notify-send`)

## Configuration

Edit the configurable properties at the top of `Bar.qml`:

```qml
// Configurable apps (change these to your preferred tools)
property string terminalApp: "kitty"
property string networkManager: "nmtui"        // Alternatives: nm-connection-editor, iwctl
property string bluetoothManager: "bluetui"    // Alternatives: blueman-manager, bluetoothctl
```

## Usage

```bash
quickshell
```

## Roadmap / TODO

- [ ] **Modularity Settings** - In-app configuration for bar components and themes
- [ ] **Clock Format** - Customizable time format and suffix (e.g., "Uhr", "AM/PM")
- [ ] **Network Manager Picker** - GUI for selecting WiFi networks
- [ ] **Bluetooth Picker** - GUI for pairing/connecting Bluetooth devices
- [ ] **Terminal Picker** - Configurable terminal selection dialog

## License

MIT
