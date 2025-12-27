import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

Scope {
    id: root

    // Shared state properties
    property string currentTime: ""
    property int audioVolume: 0
    property bool audioMuted: false
    property string networkStatus: "disconnected"
    property string networkIcon: "󰤭"
    property bool bluetoothEnabled: true
    property bool bluetoothConnected: false
    property int batteryPercent: 100
    property bool batteryCharging: false

    // Control Center state
    property bool controlCenterVisible: false
    property string batteryTimeRemaining: ""
    property string powerProfile: "Balanced"

    // System info
    property int cpuUsage: 0
    property int cpuTemp: 0
    property int ramUsage: 0

    // Notification state
    property bool notificationCenterVisible: false
    property int unreadCount: 0

    // Settings state
    property bool settingsVisible: false
    property int settingsTab: 0  // 0=Apps, 1=Time, 2=Thresholds, 3=Limits
    property bool timeSuffixEnabled: true
    property int maxLauncherResults: 5
    property int maxActiveNotifications: 5

    // Warning thresholds
    property int cpuWarningThreshold: 80
    property int tempWarningThreshold: 70
    property int ramWarningThreshold: 80
    property int batteryCriticalThreshold: 15

    // Launcher state
    property bool launcherVisible: false
    property string launcherQuery: ""
    property var launcherResults: []      // All matching results (max 5)
    property int launcherSelectedIndex: 0 // Currently selected result
    property var launcherResult: launcherResults.length > 0 ? launcherResults[launcherSelectedIndex] : null

    // Ghost-text completion state
    property string launcherOriginalQuery: ""   // Query before Tab-completion (for cycling)
    property bool launcherCompletionMode: false // Are we in Tab-cycle mode?
    property string launcherGhostText: {
        if (!launcherResult) return ""
        // Calculator: show " = result"
        if (launcherResult.type === "calc") {
            return launcherResult.name  // Already formatted as "= X"
        }
        // App: show remaining characters if prefix matches
        let name = launcherResult.name
        let query = launcherQuery
        if (name.toLowerCase().startsWith(query.toLowerCase())) {
            return name.substring(query.length)
        }
        return ""
    }

    // Configurable apps (change these to your preferred tools)
    property string terminalApp: "kitty"
    property string networkManager: "nmtui"        // Alternatives: nm-connection-editor, iwctl
    property string bluetoothManager: "bluetui"    // Alternatives: blueman-manager, bluetoothctl

    // Time format configuration (for future Settings menu)
    property string timeFormat: "24h"              // "24h" or "12h"
    property string timeSuffix: " Uhr"             // Suffix after time (e.g., " Uhr", " AM/PM" handled by format)

    // Format time helper function
    function formatTime(date) {
        if (!date) date = new Date()
        let hours = date.getHours()
        let minutes = date.getMinutes().toString().padStart(2, '0')

        if (root.timeFormat === "12h") {
            let period = hours >= 12 ? "PM" : "AM"
            hours = hours % 12 || 12
            return hours + ":" + minutes + " " + period
        }
        return hours.toString().padStart(2, '0') + ":" + minutes + root.timeSuffix
    }

    // Update launcher results based on query (max 5 results)
    function updateLauncherResult() {
        let query = root.launcherQuery.trim()
        if (query.length === 0) {
            root.launcherResults = []
            root.launcherSelectedIndex = 0
            return
        }

        let results = []

        // Check if it's a math expression (numbers and operators only)
        if (/^[\d\s\+\-\*\/\(\)\.\,\%]+$/.test(query)) {
            try {
                let expr = query.replace(/,/g, '.').replace(/%/g, '/100')
                let calcResult = Function('"use strict"; return (' + expr + ')')()
                if (typeof calcResult === 'number' && !isNaN(calcResult)) {
                    results.push({ type: "calc", name: "= " + calcResult, entry: null })
                }
            } catch(e) {}
        }

        // Search in applications (startsWith first, then includes)
        let queryLower = query.toLowerCase()
        let apps = DesktopEntries.applications.values
        let startsWithMatches = []
        let containsMatches = []

        for (let i = 0; i < apps.length; i++) {
            let nameLower = apps[i].name.toLowerCase()
            if (nameLower.startsWith(queryLower)) {
                startsWithMatches.push({ type: "app", name: apps[i].name, entry: apps[i] })
            } else if (nameLower.includes(queryLower)) {
                containsMatches.push({ type: "app", name: apps[i].name, entry: apps[i] })
            }
        }

        // Combine: calc first, then startsWith, then contains (max 5 total)
        results = results.concat(startsWithMatches, containsMatches).slice(0, 5)

        root.launcherResults = results
        // Reset selection if out of bounds
        if (root.launcherSelectedIndex >= results.length) {
            root.launcherSelectedIndex = 0
        }
    }

    // Execute launcher result
    function executeLauncherResult() {
        if (!root.launcherResult) return

        if (root.launcherResult.type === "app" && root.launcherResult.entry) {
            root.launcherResult.entry.execute()
        }
        // For calc, result is just displayed (could copy to clipboard later)

        root.launcherVisible = false
        root.launcherQuery = ""
        root.launcherResults = []
        root.launcherSelectedIndex = 0
        root.launcherCompletionMode = false
        root.launcherOriginalQuery = ""
    }

    // Navigate launcher results
    function launcherNextResult() {
        if (root.launcherResults.length > 1) {
            root.launcherSelectedIndex = (root.launcherSelectedIndex + 1) % root.launcherResults.length
        }
    }

    function launcherPrevResult() {
        if (root.launcherResults.length > 1) {
            root.launcherSelectedIndex = (root.launcherSelectedIndex - 1 + root.launcherResults.length) % root.launcherResults.length
        }
    }

    // Notification history model
    ListModel {
        id: notificationHistory
    }

    // Active popup notifications (max 5)
    ListModel {
        id: activeNotificationsModel
    }

    // NotificationServer
    NotificationServer {
        id: notificationServer

        onNotification: function(notification) {
            // Skip notifications carried over from previous reload
            if (notification.lastGeneration) return

            // Copy data (don't store object reference)
            let notifData = {
                notifId: notification.id,
                summary: notification.summary || "",
                body: notification.body || "",
                appName: notification.appName || "Notification",
                appIcon: notification.appIcon || "",
                image: notification.image || "",
                urgency: notification.urgency || 1,
                timestamp: root.formatTime(new Date()),
                desktopEntry: notification.desktopEntry || "",
                expireTime: Date.now() + (notification.expireTimeout > 0 ? notification.expireTimeout * 1000 : 5000)
            }

            // Add to history (skip transient notifications)
            if (!notification.transient) {
                notificationHistory.insert(0, notifData)
                root.unreadCount++
            }

            // Update active popups (max 5)
            if (activeNotificationsModel.count < 5) {
                activeNotificationsModel.append(notifData)
            }

            // Keep notification alive
            notification.tracked = true
        }
    }

    // Auto-expire timer for popups
    Timer {
        interval: 1000
        running: activeNotificationsModel.count > 0
        repeat: true
        onTriggered: {
            let now = Date.now()
            for (let i = activeNotificationsModel.count - 1; i >= 0; i--) {
                let notif = activeNotificationsModel.get(i)
                // Expire if timeout passed and not critical
                if (notif.urgency !== 2 && now > notif.expireTime) {
                    activeNotificationsModel.remove(i)
                }
            }
        }
    }

    function removeActiveNotification(id) {
        for (let i = 0; i < activeNotificationsModel.count; i++) {
            if (activeNotificationsModel.get(i).notifId === id) {
                activeNotificationsModel.remove(i)
                break
            }
        }
    }

    function focusAppWorkspace(desktopEntry, appName) {
        let searchTerm = desktopEntry || appName
        if (searchTerm) {
            HyprlandIpc.dispatch("focuswindow class:" + searchTerm.toLowerCase())
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }

            // Waybar: height 28, margin-top 4, margin-left/right 8
            margins {
                top: 4
                left: 8
                right: 8
            }

            implicitHeight: 28
            color: "transparent"

            // Main bar container with background
            Rectangle {
                id: barBackground
                anchors.fill: parent
                color: Qt.rgba(20/255, 20/255, 25/255, 0.85)
                radius: 10

                // Content with padding
                Item {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 2
                    anchors.bottomMargin: 2

                    // LEFT: Clock + Heart
                    Row {
                        id: leftSection
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        // Clock
                        Text {
                            id: clockText
                            text: root.currentTime
                            color: "#ffffff"
                            font.family: "SF Pro Display, Inter, JetBrains Mono Nerd Font"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Heart icon
                        Text {
                            text: ""
                            color: "#3b82f6"
                            font.family: "JetBrains Mono Nerd Font"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // CENTER: Workspace dots (FIXED position, never moves!)
                    Row {
                        id: centerSection
                        anchors.centerIn: parent
                        spacing: 6

                        Repeater {
                            // Filter out special workspaces (negative IDs)
                            model: [...Hyprland.workspaces.values].filter(ws => ws.id > 0).sort((a, b) => a.id - b.id)

                            Text {
                                required property var modelData
                                property bool isActive: modelData.focused

                                text: isActive ? "●" : "○"
                                color: isActive ? "#ffffff" : "#666666"
                                font.pixelSize: 8
                                font.family: "sans-serif"

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onClicked: HyprlandIpc.dispatch("workspace " + modelData.id)
                                    onEntered: parent.color = parent.isActive ? "#ffffff" : "#aaaaaa"
                                    onExited: parent.color = parent.isActive ? "#ffffff" : "#666666"
                                }
                            }
                        }
                    }

                    // LAUNCHER: Fixed start position, extends rightward
                    Item {
                        id: launcherSection
                        visible: root.launcherVisible
                        // Fixed left edge at midpoint between dots and right section
                        x: (centerSection.x + centerSection.width + rightSection.x) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: launcherContent.implicitWidth
                        height: 18

                        Row {
                            id: launcherContent
                            spacing: 0
                            anchors.verticalCenter: parent.verticalCenter

                            TextInput {
                                id: launcherInput
                                width: contentWidth > 0 ? contentWidth + 1 : 2
                                height: 18
                                verticalAlignment: TextInput.AlignVCenter
                                color: "#ffffff"
                                font.pixelSize: 11
                                font.family: "JetBrains Mono Nerd Font"
                                cursorVisible: true
                                clip: false
                                text: root.launcherQuery

                                cursorDelegate: Rectangle {
                                    width: 1
                                    color: "#3b82f6"
                                    visible: launcherInput.cursorVisible
                                }

                                Connections {
                                    target: root
                                    function onLauncherVisibleChanged() {
                                        if (root.launcherVisible) launcherInput.forceActiveFocus()
                                    }
                                }

                                onTextChanged: {
                                    if (root.launcherCompletionMode) {
                                        let expectedName = root.launcherResult ? root.launcherResult.name : ""
                                        if (text !== expectedName) {
                                            root.launcherCompletionMode = false
                                            root.launcherOriginalQuery = ""
                                        }
                                    }
                                    root.launcherQuery = text
                                    if (!root.launcherCompletionMode) root.updateLauncherResult()
                                }

                                Keys.onReturnPressed: root.executeLauncherResult()
                                Keys.onEnterPressed: root.executeLauncherResult()
                                Keys.onEscapePressed: {
                                    root.launcherVisible = false
                                    root.launcherQuery = ""
                                    root.launcherResults = []
                                    root.launcherSelectedIndex = 0
                                    root.launcherCompletionMode = false
                                    root.launcherOriginalQuery = ""
                                }
                                Keys.onTabPressed: (event) => {
                                    if (!root.launcherResult) { event.accepted = true; return }
                                    if (!root.launcherCompletionMode) {
                                        root.launcherOriginalQuery = root.launcherQuery
                                        root.launcherCompletionMode = true
                                        root.launcherQuery = root.launcherResult.name
                                        launcherInput.text = root.launcherResult.name
                                    } else {
                                        root.launcherSelectedIndex = (root.launcherSelectedIndex + 1) % root.launcherResults.length
                                        root.launcherQuery = root.launcherResult.name
                                        launcherInput.text = root.launcherResult.name
                                    }
                                    event.accepted = true
                                }
                                Keys.onBacktabPressed: (event) => {
                                    if (!root.launcherResult) { event.accepted = true; return }
                                    if (!root.launcherCompletionMode) {
                                        root.launcherOriginalQuery = root.launcherQuery
                                        root.launcherCompletionMode = true
                                        root.launcherSelectedIndex = root.launcherResults.length - 1
                                    } else {
                                        root.launcherSelectedIndex = (root.launcherSelectedIndex - 1 + root.launcherResults.length) % root.launcherResults.length
                                    }
                                    root.launcherQuery = root.launcherResult.name
                                    launcherInput.text = root.launcherResult.name
                                    event.accepted = true
                                }
                                Keys.onDownPressed: {
                                    if (root.launcherResults.length > 1) {
                                        if (!root.launcherCompletionMode) {
                                            root.launcherOriginalQuery = root.launcherQuery
                                            root.launcherCompletionMode = true
                                        }
                                        root.launcherSelectedIndex = (root.launcherSelectedIndex + 1) % root.launcherResults.length
                                        root.launcherQuery = root.launcherResult.name
                                        launcherInput.text = root.launcherResult.name
                                    }
                                }
                                Keys.onUpPressed: {
                                    if (root.launcherResults.length > 1) {
                                        if (!root.launcherCompletionMode) {
                                            root.launcherOriginalQuery = root.launcherQuery
                                            root.launcherCompletionMode = true
                                            root.launcherSelectedIndex = root.launcherResults.length - 1
                                        } else {
                                            root.launcherSelectedIndex = (root.launcherSelectedIndex - 1 + root.launcherResults.length) % root.launcherResults.length
                                        }
                                        root.launcherQuery = root.launcherResult.name
                                        launcherInput.text = root.launcherResult.name
                                    }
                                }
                            }

                            // Ghost-text (bluish)
                            Text {
                                visible: root.launcherGhostText.length > 0
                                text: root.launcherGhostText
                                color: root.launcherResult && root.launcherResult.type === "calc" ? "#22c55e" : "#4a5568"
                                font.pixelSize: 11
                                font.family: "JetBrains Mono Nerd Font"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Subtle underline
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: "#4a5568"
                            opacity: 0.6
                        }
                    }

                    // Launcher focus grab - captures keyboard when launcher is visible
                    HyprlandFocusGrab {
                        id: launcherFocusGrab
                        active: root.launcherVisible
                        windows: [ panel ]
                        onCleared: {
                            root.launcherVisible = false
                            root.launcherQuery = ""
                            root.launcherResults = []
                            root.launcherSelectedIndex = 0
                            root.launcherCompletionMode = false
                            root.launcherOriginalQuery = ""
                        }
                    }

                    // RIGHT: System icons
                    Row {
                        id: rightSection
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        // System warnings (show all critical values)
                        Rectangle {
                            visible: root.cpuUsage > 70
                            color: "#ef4444"
                            radius: 6
                            height: 18
                            width: cpuWarningText.implicitWidth + 10
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                id: cpuWarningText
                                anchors.centerIn: parent
                                text: "󰻠 " + root.cpuUsage + "%"
                                color: "#ffffff"
                                font.family: "JetBrains Mono Nerd Font"
                                font.pixelSize: 11
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.controlCenterVisible = !root.controlCenterVisible
                            }
                        }

                        Rectangle {
                            visible: root.cpuTemp > 65
                            color: "#ef4444"
                            radius: 6
                            height: 18
                            width: tempWarningText.implicitWidth + 10
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                id: tempWarningText
                                anchors.centerIn: parent
                                text: "󰔏 " + root.cpuTemp + "°"
                                color: "#ffffff"
                                font.family: "JetBrains Mono Nerd Font"
                                font.pixelSize: 11
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.controlCenterVisible = !root.controlCenterVisible
                            }
                        }

                        Rectangle {
                            visible: root.ramUsage > 75
                            color: "#ef4444"
                            radius: 6
                            height: 18
                            width: ramWarningText.implicitWidth + 10
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                id: ramWarningText
                                anchors.centerIn: parent
                                text: "󰘚 " + root.ramUsage + "%"
                                color: "#ffffff"
                                font.family: "JetBrains Mono Nerd Font"
                                font.pixelSize: 11
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.controlCenterVisible = !root.controlCenterVisible
                            }
                        }

                        // Notification bell icon (only visible when there are notifications)
                        Item {
                            visible: root.unreadCount > 0 || activeNotificationsModel.count > 0
                            width: notifIcon.implicitWidth + (root.unreadCount > 0 ? notifBadgeRect.width + 2 : 0)
                            height: 20
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                id: notifIcon
                                text: root.unreadCount > 0 ? "󰂚" : "󰂜"
                                color: "#ffffff"
                                font.family: "JetBrains Mono Nerd Font"
                                font.pixelSize: 14
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Rectangle {
                                id: notifBadgeRect
                                visible: root.unreadCount > 0
                                anchors.left: notifIcon.right
                                anchors.leftMargin: 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: notifBadgeText.implicitWidth + 6
                                height: 14
                                radius: 7
                                color: "#ef4444"

                                Text {
                                    id: notifBadgeText
                                    anchors.centerIn: parent
                                    text: root.unreadCount > 99 ? "99+" : root.unreadCount
                                    color: "#ffffff"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.notificationCenterVisible = !root.notificationCenterVisible
                                    if (root.notificationCenterVisible) {
                                        root.unreadCount = 0
                                        root.controlCenterVisible = false
                                    }
                                }
                            }
                        }

                        // PulseAudio/Volume
                        Text {
                            id: volumeIcon
                            text: root.audioMuted ? "󰝟" : (root.audioVolume > 66 ? "󰕾" : (root.audioVolume > 33 ? "󰖀" : "󰕿"))
                            color: "#ffffff"
                            font.family: "JetBrains Mono Nerd Font"
                            font.pixelSize: 14
                            anchors.verticalCenter: parent.verticalCenter

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.controlCenterVisible = !root.controlCenterVisible
                            }
                        }

                        // Network
                        Text {
                            id: networkIconText
                            text: root.networkIcon
                            color: "#ffffff"
                            font.family: "JetBrains Mono Nerd Font"
                            font.pixelSize: 14
                            anchors.verticalCenter: parent.verticalCenter

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.controlCenterVisible = !root.controlCenterVisible
                            }
                        }

                        // Bluetooth (only visible when enabled)
                        Text {
                            id: bluetoothIcon
                            visible: root.bluetoothEnabled
                            text: root.bluetoothConnected ? "󰂱" : "󰂯"
                            color: "#ffffff"
                            font.family: "JetBrains Mono Nerd Font"
                            font.pixelSize: 14
                            anchors.verticalCenter: parent.verticalCenter

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.controlCenterVisible = !root.controlCenterVisible
                            }
                        }

                        // Battery
                        Text {
                            id: batteryIcon
                            text: {
                                if (root.batteryCharging) return "󰂄"
                                if (root.batteryPercent >= 90) return "󰁹"
                                if (root.batteryPercent >= 80) return "󰂂"
                                if (root.batteryPercent >= 70) return "󰂁"
                                if (root.batteryPercent >= 60) return "󰂀"
                                if (root.batteryPercent >= 50) return "󰁿"
                                if (root.batteryPercent >= 40) return "󰁾"
                                if (root.batteryPercent >= 30) return "󰁽"
                                if (root.batteryPercent >= 20) return "󰁼"
                                if (root.batteryPercent >= 10) return "󰁻"
                                return "󰁺"
                            }
                            color: root.batteryCharging ? "#22c55e" :
                                   root.batteryPercent < 20 ? "#ef4444" : "#ffffff"
                            font.family: "JetBrains Mono Nerd Font"
                            font.pixelSize: 14
                            anchors.verticalCenter: parent.verticalCenter

                            // Blink animation for critical battery
                            SequentialAnimation on opacity {
                                running: root.batteryPercent <= 5 && !root.batteryCharging
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 500 }
                                NumberAnimation { to: 1.0; duration: 500 }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.controlCenterVisible = !root.controlCenterVisible
                            }
                        }
                    }
                }
            }

            // === CONTROL CENTER POPUP (Compact Design) ===
            PopupWindow {
                id: controlCenterPopup

                anchor.window: panel
                anchor.rect.x: panel.width - implicitWidth - 2
                anchor.rect.y: panel.height + 4

                implicitWidth: 260
                implicitHeight: popupContent.implicitHeight

                visible: root.controlCenterVisible
                color: "transparent"

                property real animatedOpacity: root.controlCenterVisible ? 1.0 : 0.0
                property real slideOffset: root.controlCenterVisible ? 0 : -10

                Behavior on animatedOpacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                Behavior on slideOffset { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                HyprlandFocusGrab {
                    active: root.controlCenterVisible
                    windows: [ controlCenterPopup ]
                    onCleared: root.controlCenterVisible = false
                }

                // ESC to close
                Item {
                    focus: root.controlCenterVisible
                    Keys.onEscapePressed: root.controlCenterVisible = false
                }

                Rectangle {
                    id: popupContent
                    anchors.fill: parent
                    color: Qt.rgba(20/255, 20/255, 25/255, 1.0)
                    radius: 10
                    border.color: Qt.rgba(255, 255, 255, 0.08)
                    border.width: 1
                    opacity: controlCenterPopup.animatedOpacity
                    transform: Translate { y: controlCenterPopup.slideOffset }

                    implicitHeight: compactColumn.implicitHeight + 20

                    Column {
                        id: compactColumn
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        // Row 1: Quick Toggle Grid (2x2)
                        Grid {
                            width: parent.width
                            columns: 4
                            spacing: 6

                            // WiFi Toggle
                            Rectangle {
                                width: (parent.width - 18) / 4; height: 36; radius: 6
                                color: root.networkConnected ? "#3b82f6" : Qt.rgba(255, 255, 255, 0.08)
                                Text {
                                    anchors.centerIn: parent
                                    text: root.networkConnected ? "󰤨" : "󰤭"
                                    color: root.networkConnected ? "#ffffff" : "#888888"
                                    font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 16
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.exec(["sh", "-c", "nmcli networking " + (root.networkConnected ? "off" : "on")])
                                }
                            }

                            // Bluetooth Toggle
                            Rectangle {
                                width: (parent.width - 18) / 4; height: 36; radius: 6
                                color: root.bluetoothConnected ? "#3b82f6" : Qt.rgba(255, 255, 255, 0.08)
                                Text {
                                    anchors.centerIn: parent
                                    text: root.bluetoothConnected ? "󰂯" : "󰂲"
                                    color: root.bluetoothConnected ? "#ffffff" : "#888888"
                                    font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 16
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.exec(["sh", "-c", "bluetoothctl power " + (root.bluetoothConnected ? "off" : "on")])
                                }
                            }

                            // Mute Toggle
                            Rectangle {
                                width: (parent.width - 18) / 4; height: 36; radius: 6
                                color: root.audioMuted ? "#ef4444" : Qt.rgba(255, 255, 255, 0.08)
                                Text {
                                    anchors.centerIn: parent
                                    text: root.audioMuted ? "󰝟" : "󰕾"
                                    color: root.audioMuted ? "#ffffff" : "#888888"
                                    font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 16
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: muteProc.running = true
                                }
                            }

                            // Settings
                            Rectangle {
                                width: (parent.width - 18) / 4; height: 36; radius: 6
                                color: Qt.rgba(255, 255, 255, 0.08)
                                Text {
                                    anchors.centerIn: parent; text: "󰒓"
                                    color: "#888888"; font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 16
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.controlCenterVisible = false; root.settingsVisible = true }
                                }
                            }
                        }

                        // Row 2: Volume Slider (compact)
                        Row {
                            width: parent.width; height: 28; spacing: 8
                            Text {
                                text: root.audioMuted ? "󰝟" : "󰕾"
                                color: "#3b82f6"; font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 14
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Item {
                                width: parent.width - 70; height: 20
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width; height: 4; radius: 2
                                    color: Qt.rgba(255, 255, 255, 0.2)
                                    Rectangle {
                                        width: parent.width * (root.audioVolume / 100); height: parent.height
                                        radius: 2; color: "#3b82f6"
                                    }
                                    Rectangle {
                                        x: parent.width * (root.audioVolume / 100) - 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 12; height: 12; radius: 6; color: "#ffffff"
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => { var v = Math.round((mouse.x / width) * 100); setVolumeProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v + "%"]; setVolumeProc.running = true }
                                    onPositionChanged: (mouse) => { if (pressed) { var v = Math.round((mouse.x / width) * 100); setVolumeProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v + "%"]; setVolumeProc.running = true } }
                                }
                            }
                            Text {
                                text: root.audioVolume + "%"
                                color: "#888888"; font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Row 3: Battery + Power Profile
                        Item {
                            width: parent.width; height: 28
                            Row {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                spacing: 6; height: parent.height
                                Text {
                                    text: root.batteryCharging ? "󰂄" : (root.batteryPercent >= 80 ? "󰁹" : root.batteryPercent >= 40 ? "󰁾" : "󰁺")
                                    color: root.batteryCharging ? "#22c55e" : (root.batteryPercent < 20 ? "#ef4444" : "#ffffff")
                                    font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: root.batteryPercent + "%" + (root.batteryTimeRemaining ? " • " + root.batteryTimeRemaining : "")
                                    color: "#888888"; font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Row {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Repeater {
                                    model: [
                                        { icon: "󰾆", profile: "power-saver" },
                                        { icon: "󰾅", profile: "balanced" },
                                        { icon: "󰓅", profile: "performance" }
                                    ]
                                    Rectangle {
                                        required property var modelData
                                        width: 28; height: 24; radius: 4
                                        color: root.powerProfile === modelData.profile ? "#3b82f6" : Qt.rgba(255, 255, 255, 0.08)
                                        Text {
                                            anchors.centerIn: parent; text: modelData.icon
                                            color: root.powerProfile === modelData.profile ? "#ffffff" : "#666666"
                                            font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 12
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: { setPowerProfileProc.command = ["powerprofilesctl", "set", modelData.profile]; setPowerProfileProc.running = true }
                                        }
                                    }
                                }
                            }
                        }

                        // Row 4: System Stats (inline)
                        Row {
                            width: parent.width; height: 20
                            spacing: 0
                            anchors.horizontalCenter: parent.horizontalCenter

                            Row {
                                spacing: 4; height: parent.height
                                Text { text: "󰻠"; color: root.cpuUsage > root.cpuWarningThreshold ? "#ef4444" : "#3b82f6"; font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: root.cpuUsage + "%"; color: "#888888"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Text { text: " │ "; color: "#444444"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                            Row {
                                spacing: 4; height: parent.height
                                Text { text: "󰔏"; color: root.cpuTemp > root.tempWarningThreshold ? "#ef4444" : (root.cpuTemp > 50 ? "#f59e0b" : "#22c55e"); font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: root.cpuTemp + "°C"; color: "#888888"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Text { text: " │ "; color: "#444444"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                            Row {
                                spacing: 4; height: parent.height
                                Text { text: "󰘚"; color: root.ramUsage > root.ramWarningThreshold ? "#ef4444" : "#22c55e"; font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: root.ramUsage + "%"; color: "#888888"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }

                        // Row 5: Lock & Power (compact)
                        Row {
                            width: parent.width; height: 32; spacing: 6
                            Rectangle {
                                width: (parent.width - 6) / 2; height: 32; radius: 6
                                color: Qt.rgba(168, 85, 247, 0.15)
                                Row {
                                    anchors.centerIn: parent; spacing: 6; height: parent.height
                                    Text { text: "󰌾"; color: "#a855f7"; font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "Lock"; color: "#a855f7"; font.pixelSize: 12; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.controlCenterVisible = false; lockProc.running = true } }
                            }
                            Rectangle {
                                width: (parent.width - 6) / 2; height: 32; radius: 6
                                color: Qt.rgba(239, 68, 68, 0.15)
                                Row {
                                    anchors.centerIn: parent; spacing: 6; height: parent.height
                                    Text { text: "󰐥"; color: "#ef4444"; font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "Power"; color: "#ef4444"; font.pixelSize: 12; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.controlCenterVisible = false; shutdownProc.running = true } }
                            }
                        }
                    }
                }
            }
            // === SETTINGS POPUP ===
            PopupWindow {
                id: settingsPopup

                anchor.window: panel
                anchor.rect.x: (panel.width - implicitWidth) / 2
                anchor.rect.y: panel.height + 4

                implicitWidth: 400
                implicitHeight: settingsContent.implicitHeight + 24

                visible: root.settingsVisible
                color: "transparent"

                property real animatedOpacity: root.settingsVisible ? 1.0 : 0.0
                property real slideOffset: root.settingsVisible ? 0 : -10

                Behavior on animatedOpacity {
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }

                Behavior on slideOffset {
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }

                HyprlandFocusGrab {
                    active: root.settingsVisible
                    windows: [ settingsPopup ]
                    onCleared: root.settingsVisible = false
                }

                // ESC to close
                Item {
                    focus: root.settingsVisible
                    Keys.onEscapePressed: root.settingsVisible = false
                }

                Rectangle {
                    id: settingsContent
                    anchors.fill: parent
                    color: Qt.rgba(20/255, 20/255, 25/255, 1.0)
                    radius: 10
                    border.color: Qt.rgba(255, 255, 255, 0.08)
                    border.width: 1
                    opacity: settingsPopup.animatedOpacity
                    transform: Translate { y: settingsPopup.slideOffset }

                    implicitHeight: settingsColumn.implicitHeight + 32

                    // Close button - top right
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 8
                        width: 24; height: 24; radius: 12
                        color: settingsCloseHover.containsMouse ? Qt.rgba(255, 255, 255, 0.1) : "transparent"
                        z: 10
                        Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            color: settingsCloseHover.containsMouse ? "#ffffff" : "#888888"
                            font.family: "JetBrains Mono Nerd Font"
                            font.pixelSize: 14
                        }
                        MouseArea {
                            id: settingsCloseHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.settingsVisible = false
                        }
                    }

                    Column {
                        id: settingsColumn
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 16

                        // Header
                        Row {
                            width: parent.width
                            spacing: 10

                            Text {
                                text: "󰒓"
                                color: "#3b82f6"
                                font.family: "JetBrains Mono Nerd Font"
                                font.pixelSize: 20
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "Settings"
                                color: "#ffffff"
                                font.pixelSize: 18
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Tab Navigation
                        Row {
                            width: parent.width
                            spacing: 4

                            Repeater {
                                model: [
                                    { icon: "󰣆", label: "Apps" },
                                    { icon: "󰥔", label: "Time" },
                                    { icon: "󰀦", label: "Alerts" },
                                    { icon: "󰃀", label: "Limits" }
                                ]

                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: (parent.width - 12) / 4
                                    height: 32
                                    radius: 6
                                    color: root.settingsTab === index ? "#3b82f6" : Qt.rgba(255, 255, 255, 0.05)

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.icon
                                        color: root.settingsTab === index ? "#ffffff" : "#888888"
                                        font.family: "JetBrains Mono Nerd Font"
                                        font.pixelSize: 14
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.settingsTab = index
                                    }
                                }
                            }
                        }

                        // === TAB 0: APPS ===
                        Column {
                            visible: root.settingsTab === 0
                            width: parent.width
                            spacing: 12

                            Column {
                                width: parent.width
                                spacing: 4
                                Text { text: "Terminal"; color: "#888888"; font.pixelSize: 11 }
                                Rectangle {
                                    width: parent.width; height: 32; radius: 6
                                    color: Qt.rgba(255, 255, 255, 0.08)
                                    border.color: termInput.activeFocus ? "#3b82f6" : "transparent"
                                    TextInput {
                                        id: termInput
                                        anchors.fill: parent; anchors.margins: 8
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: "#ffffff"; font.pixelSize: 12
                                        text: root.terminalApp
                                        onTextChanged: root.terminalApp = text
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 4
                                Text { text: "Network Manager"; color: "#888888"; font.pixelSize: 11 }
                                Rectangle {
                                    width: parent.width; height: 32; radius: 6
                                    color: Qt.rgba(255, 255, 255, 0.08)
                                    border.color: netInput.activeFocus ? "#3b82f6" : "transparent"
                                    TextInput {
                                        id: netInput
                                        anchors.fill: parent; anchors.margins: 8
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: "#ffffff"; font.pixelSize: 12
                                        text: root.networkManager
                                        onTextChanged: root.networkManager = text
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 4
                                Text { text: "Bluetooth Manager"; color: "#888888"; font.pixelSize: 11 }
                                Rectangle {
                                    width: parent.width; height: 32; radius: 6
                                    color: Qt.rgba(255, 255, 255, 0.08)
                                    border.color: btInput.activeFocus ? "#3b82f6" : "transparent"
                                    TextInput {
                                        id: btInput
                                        anchors.fill: parent; anchors.margins: 8
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: "#ffffff"; font.pixelSize: 12
                                        text: root.bluetoothManager
                                        onTextChanged: root.bluetoothManager = text
                                    }
                                }
                            }
                        }

                        // === TAB 1: TIME ===
                        Column {
                            visible: root.settingsTab === 1
                            width: parent.width
                            spacing: 12

                            Item {
                                width: parent.width; height: 28
                                Text {
                                    text: "Format"
                                    color: "#888888"; font.pixelSize: 12
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    Rectangle {
                                        width: 44; height: 28; radius: 6
                                        color: root.timeFormat === "24h" ? "#3b82f6" : Qt.rgba(255, 255, 255, 0.1)
                                        Text { anchors.centerIn: parent; text: "24h"; color: "#ffffff"; font.pixelSize: 11 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.timeFormat = "24h" }
                                    }
                                    Rectangle {
                                        width: 44; height: 28; radius: 6
                                        color: root.timeFormat === "12h" ? "#3b82f6" : Qt.rgba(255, 255, 255, 0.1)
                                        Text { anchors.centerIn: parent; text: "12h"; color: "#ffffff"; font.pixelSize: 11 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.timeFormat = "12h" }
                                    }
                                }
                            }

                            Column {
                                visible: root.timeFormat === "24h"
                                width: parent.width
                                spacing: 8

                                Item {
                                    width: parent.width; height: 24
                                    Text { text: "Show Suffix"; color: "#888888"; font.pixelSize: 12; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                                    Rectangle {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: 44; height: 24; radius: 12
                                        color: root.timeSuffixEnabled ? "#3b82f6" : Qt.rgba(255, 255, 255, 0.2)
                                        Rectangle {
                                            x: root.timeSuffixEnabled ? parent.width - width - 2 : 2; y: 2
                                            width: 20; height: 20; radius: 10; color: "#ffffff"
                                            Behavior on x { NumberAnimation { duration: 100 } }
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.timeSuffixEnabled = !root.timeSuffixEnabled }
                                    }
                                }

                                Rectangle {
                                    visible: root.timeSuffixEnabled
                                    width: parent.width; height: 32; radius: 6
                                    color: Qt.rgba(255, 255, 255, 0.08)
                                    TextInput {
                                        anchors.fill: parent; anchors.margins: 8
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: "#ffffff"; font.pixelSize: 12
                                        text: root.timeSuffix
                                        onTextChanged: root.timeSuffix = text
                                    }
                                }
                            }
                        }

                        // === TAB 2: ALERTS ===
                        Column {
                            visible: root.settingsTab === 2
                            width: parent.width
                            spacing: 16

                            Column {
                                width: parent.width; spacing: 4
                                Item {
                                    width: parent.width; height: 16
                                    Text { text: "CPU Warning"; color: "#888888"; font.pixelSize: 11; anchors.left: parent.left }
                                    Text { text: root.cpuWarningThreshold + "%"; color: "#ffffff"; font.pixelSize: 11; anchors.right: parent.right }
                                }
                                Item {
                                    width: parent.width; height: 20
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width; height: 6; radius: 3
                                        color: Qt.rgba(255, 255, 255, 0.2)
                                        Rectangle { width: parent.width * (root.cpuWarningThreshold / 100); height: parent.height; radius: 3; color: "#ef4444" }
                                        Rectangle { x: parent.width * (root.cpuWarningThreshold / 100) - 7; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 7; color: "#ffffff" }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: (mouse) => { root.cpuWarningThreshold = Math.max(10, Math.min(100, Math.round((mouse.x / width) * 100))) }
                                        onPositionChanged: (mouse) => { if (pressed) root.cpuWarningThreshold = Math.max(10, Math.min(100, Math.round((mouse.x / width) * 100))) }
                                    }
                                }
                            }

                            Column {
                                width: parent.width; spacing: 4
                                Item {
                                    width: parent.width; height: 16
                                    Text { text: "Temperature"; color: "#888888"; font.pixelSize: 11; anchors.left: parent.left }
                                    Text { text: root.tempWarningThreshold + "°C"; color: "#ffffff"; font.pixelSize: 11; anchors.right: parent.right }
                                }
                                Item {
                                    width: parent.width; height: 20
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width; height: 6; radius: 3
                                        color: Qt.rgba(255, 255, 255, 0.2)
                                        Rectangle { width: parent.width * (root.tempWarningThreshold / 100); height: parent.height; radius: 3; color: "#f59e0b" }
                                        Rectangle { x: parent.width * (root.tempWarningThreshold / 100) - 7; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 7; color: "#ffffff" }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: (mouse) => { root.tempWarningThreshold = Math.max(40, Math.min(100, Math.round((mouse.x / width) * 100))) }
                                        onPositionChanged: (mouse) => { if (pressed) root.tempWarningThreshold = Math.max(40, Math.min(100, Math.round((mouse.x / width) * 100))) }
                                    }
                                }
                            }

                            Column {
                                width: parent.width; spacing: 4
                                Item {
                                    width: parent.width; height: 16
                                    Text { text: "RAM Warning"; color: "#888888"; font.pixelSize: 11; anchors.left: parent.left }
                                    Text { text: root.ramWarningThreshold + "%"; color: "#ffffff"; font.pixelSize: 11; anchors.right: parent.right }
                                }
                                Item {
                                    width: parent.width; height: 20
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width; height: 6; radius: 3
                                        color: Qt.rgba(255, 255, 255, 0.2)
                                        Rectangle { width: parent.width * (root.ramWarningThreshold / 100); height: parent.height; radius: 3; color: "#a855f7" }
                                        Rectangle { x: parent.width * (root.ramWarningThreshold / 100) - 7; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 7; color: "#ffffff" }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: (mouse) => { root.ramWarningThreshold = Math.max(20, Math.min(100, Math.round((mouse.x / width) * 100))) }
                                        onPositionChanged: (mouse) => { if (pressed) root.ramWarningThreshold = Math.max(20, Math.min(100, Math.round((mouse.x / width) * 100))) }
                                    }
                                }
                            }

                            Column {
                                width: parent.width; spacing: 4
                                Item {
                                    width: parent.width; height: 16
                                    Text { text: "Battery Critical"; color: "#888888"; font.pixelSize: 11; anchors.left: parent.left }
                                    Text { text: root.batteryCriticalThreshold + "%"; color: "#ffffff"; font.pixelSize: 11; anchors.right: parent.right }
                                }
                                Item {
                                    width: parent.width; height: 20
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width; height: 6; radius: 3
                                        color: Qt.rgba(255, 255, 255, 0.2)
                                        Rectangle { width: parent.width * (root.batteryCriticalThreshold / 30); height: parent.height; radius: 3; color: "#ef4444" }
                                        Rectangle { x: parent.width * (root.batteryCriticalThreshold / 30) - 7; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 7; color: "#ffffff" }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: (mouse) => { root.batteryCriticalThreshold = Math.max(1, Math.min(30, Math.round((mouse.x / width) * 30))) }
                                        onPositionChanged: (mouse) => { if (pressed) root.batteryCriticalThreshold = Math.max(1, Math.min(30, Math.round((mouse.x / width) * 30))) }
                                    }
                                }
                            }
                        }

                        // === TAB 3: LIMITS ===
                        Column {
                            visible: root.settingsTab === 3
                            width: parent.width
                            spacing: 16

                            Item {
                                width: parent.width; height: 28
                                Text { text: "Launcher Results"; color: "#888888"; font.pixelSize: 12; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                                Row {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                    Rectangle {
                                        width: 28; height: 28; radius: 6
                                        color: root.maxLauncherResults > 1 ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(255, 255, 255, 0.05)
                                        Text { anchors.centerIn: parent; text: "−"; color: "#ffffff"; font.pixelSize: 14 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.maxLauncherResults > 1) root.maxLauncherResults-- }
                                    }
                                    Rectangle {
                                        width: 36; height: 28; radius: 6; color: Qt.rgba(255, 255, 255, 0.08)
                                        Text { anchors.centerIn: parent; text: root.maxLauncherResults; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.Medium }
                                    }
                                    Rectangle {
                                        width: 28; height: 28; radius: 6
                                        color: root.maxLauncherResults < 10 ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(255, 255, 255, 0.05)
                                        Text { anchors.centerIn: parent; text: "+"; color: "#ffffff"; font.pixelSize: 14 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.maxLauncherResults < 10) root.maxLauncherResults++ }
                                    }
                                }
                            }

                            Item {
                                width: parent.width; height: 28
                                Text { text: "Active Notifications"; color: "#888888"; font.pixelSize: 12; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                                Row {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                    Rectangle {
                                        width: 28; height: 28; radius: 6
                                        color: root.maxActiveNotifications > 1 ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(255, 255, 255, 0.05)
                                        Text { anchors.centerIn: parent; text: "−"; color: "#ffffff"; font.pixelSize: 14 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.maxActiveNotifications > 1) root.maxActiveNotifications-- }
                                    }
                                    Rectangle {
                                        width: 36; height: 28; radius: 6; color: Qt.rgba(255, 255, 255, 0.08)
                                        Text { anchors.centerIn: parent; text: root.maxActiveNotifications; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.Medium }
                                    }
                                    Rectangle {
                                        width: 28; height: 28; radius: 6
                                        color: root.maxActiveNotifications < 10 ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(255, 255, 255, 0.05)
                                        Text { anchors.centerIn: parent; text: "+"; color: "#ffffff"; font.pixelSize: 14 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.maxActiveNotifications < 10) root.maxActiveNotifications++ }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // === NOTIFICATION CENTER POPUP ===
            PopupWindow {
                id: notificationCenterPopup

                anchor.window: panel
                anchor.rect.x: panel.width - implicitWidth - 2
                anchor.rect.y: panel.height + 4

                implicitWidth: 360
                implicitHeight: Math.min(notifCenterContent.implicitHeight + 24, 500)

                visible: root.notificationCenterVisible
                color: "transparent"

                property real animatedOpacity: root.notificationCenterVisible ? 1.0 : 0.0
                property real slideOffset: root.notificationCenterVisible ? 0 : -10

                Behavior on animatedOpacity {
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }

                Behavior on slideOffset {
                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                }

                HyprlandFocusGrab {
                    active: root.notificationCenterVisible
                    windows: [ notificationCenterPopup ]
                    onCleared: root.notificationCenterVisible = false
                }

                // ESC to close
                Item {
                    focus: root.notificationCenterVisible
                    Keys.onEscapePressed: root.notificationCenterVisible = false
                }

                Rectangle {
                    id: notifCenterContent
                    anchors.fill: parent
                    color: Qt.rgba(20/255, 20/255, 25/255, 1.0)
                    radius: 10
                    border.color: Qt.rgba(255, 255, 255, 0.08)
                    border.width: 1
                    opacity: notificationCenterPopup.animatedOpacity
                    transform: Translate { y: notificationCenterPopup.slideOffset }

                    implicitHeight: notifCenterColumn.implicitHeight + 32

                    Column {
                        id: notifCenterColumn
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        // Header
                        Row {
                            width: parent.width

                            Text {
                                text: "Notifications"
                                color: "#ffffff"
                                font.pixelSize: 16
                                font.weight: Font.Medium
                            }

                            Item { width: parent.width - 150; height: 1 }

                            Text {
                                text: "Clear all"
                                color: "#3b82f6"
                                font.pixelSize: 12
                                visible: notificationHistory.count > 0

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        notificationHistory.clear()
                                        root.unreadCount = 0
                                        root.notificationCenterVisible = false
                                    }
                                }
                            }
                        }

                        // Empty state
                        Text {
                            visible: notificationHistory.count === 0
                            text: "No notifications"
                            color: "#888888"
                            font.pixelSize: 13
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            topPadding: 20
                        }

                        // Notification list
                        ListView {
                            id: notifListView
                            width: parent.width
                            height: Math.min(contentHeight, 380)
                            clip: true
                            spacing: 8
                            model: notificationHistory
                            visible: notificationHistory.count > 0

                            delegate: Rectangle {
                                width: notifListView.width
                                height: notifDelegateCol.implicitHeight + 20
                                radius: 8
                                color: Qt.rgba(255, 255, 255, 0.05)

                                Column {
                                    id: notifDelegateCol
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    anchors.rightMargin: 30
                                    spacing: 4

                                    Row {
                                        spacing: 8

                                        // App Icon im History-Eintrag
                                        Item {
                                            width: 16
                                            height: 16
                                            anchors.verticalCenter: parent.verticalCenter

                                            Image {
                                                id: historyIconImg
                                                anchors.fill: parent
                                                sourceSize: Qt.size(16, 16)
                                                source: {
                                                    if (model.image && model.image.length > 0) {
                                                        return model.image
                                                    }
                                                    if (model.appIcon && model.appIcon.length > 0) {
                                                        if (model.appIcon.startsWith("/") || model.appIcon.startsWith("file://")) {
                                                            return model.appIcon
                                                        }
                                                        return Quickshell.iconPath(model.appIcon)
                                                    }
                                                    return ""
                                                }
                                                visible: source != ""
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰀻"
                                                color: "#3b82f6"
                                                font.family: "JetBrains Mono Nerd Font"
                                                font.pixelSize: 14
                                                visible: !historyIconImg.visible || historyIconImg.status !== Image.Ready
                                            }
                                        }

                                        Text {
                                            text: model.appName || "Unknown"
                                            color: "#888888"
                                            font.pixelSize: 11
                                        }

                                        Text {
                                            text: "•"
                                            color: "#666666"
                                            font.pixelSize: 11
                                        }

                                        Text {
                                            text: model.timestamp
                                            color: "#666666"
                                            font.pixelSize: 11
                                        }
                                    }

                                    Text {
                                        text: model.summary || ""
                                        color: "#ffffff"
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        width: parent.width
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: model.body || ""
                                        color: "#aaaaaa"
                                        font.pixelSize: 12
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        visible: model.body && model.body.length > 0
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.focusAppWorkspace(model.desktopEntry, model.appName)
                                        root.notificationCenterVisible = false
                                    }
                                }

                                // Dismiss button
                                Text {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 8
                                    text: "󰅖"
                                    color: "#888888"
                                    font.family: "JetBrains Mono Nerd Font"
                                    font.pixelSize: 12

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: notificationHistory.remove(index)
                                    }
                                }
                            }
                        }
                    }
                }
            }

        }
    }

    // === NOTIFICATION POPUPS (separate overlay window) ===
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: notifPanel
            required property var modelData
            screen: modelData

            anchors {
                right: true
                top: true
            }

            margins {
                top: 36  // Below bar (28 + 4 + 4)
                right: 10
            }

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:notifications"

            implicitWidth: 320
            implicitHeight: activeNotificationsModel.count > 0 ? notifColumn.implicitHeight + 16 : 0

            color: "transparent"
            visible: activeNotificationsModel.count > 0

            Column {
                id: notifColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                Repeater {
                    model: activeNotificationsModel

                    Rectangle {
                        id: notifRect
                        required property int index
                        required property int notifId
                        required property string summary
                        required property string body
                        required property string appName
                        required property string appIcon
                        required property string image
                        required property string desktopEntry
                        required property int urgency

                        width: notifColumn.width
                        height: 76
                        radius: 10
                        color: Qt.rgba(20/255, 20/255, 25/255, 1.0)
                        border.color: notifRect.urgency === 2 ? "#ef4444" : Qt.rgba(255, 255, 255, 0.1)
                        border.width: 1

                        Row {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            // App Icon
                            Rectangle {
                                width: 40
                                height: 40
                                radius: 8
                                color: Qt.rgba(255, 255, 255, 0.1)
                                anchors.verticalCenter: parent.verticalCenter

                                Image {
                                    id: notifIconImg
                                    anchors.centerIn: parent
                                    width: 28
                                    height: 28
                                    sourceSize: Qt.size(28, 28)
                                    source: {
                                        // Priority: image > appIcon > fallback
                                        if (notifRect.image && notifRect.image.length > 0) {
                                            return notifRect.image
                                        }
                                        if (notifRect.appIcon && notifRect.appIcon.length > 0) {
                                            // Check if path or icon name
                                            if (notifRect.appIcon.startsWith("/") || notifRect.appIcon.startsWith("file://")) {
                                                return notifRect.appIcon
                                            }
                                            // Resolve icon name to path
                                            return Quickshell.iconPath(notifRect.appIcon)
                                        }
                                        return ""
                                    }
                                    visible: source != ""
                                }

                                // Fallback icon if no image
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰀻"
                                    color: "#3b82f6"
                                    font.family: "JetBrains Mono Nerd Font"
                                    font.pixelSize: 20
                                    visible: !notifIconImg.visible || notifIconImg.status !== Image.Ready
                                }
                            }

                            Column {
                                width: parent.width - 64
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    text: notifRect.appName
                                    color: "#888888"
                                    font.pixelSize: 11
                                }

                                Text {
                                    text: notifRect.summary
                                    color: "#ffffff"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    width: parent.width - 20
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: notifRect.body
                                    color: "#aaaaaa"
                                    font.pixelSize: 12
                                    width: parent.width - 20
                                    elide: Text.ElideRight
                                    visible: notifRect.body.length > 0
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.focusAppWorkspace(notifRect.desktopEntry, notifRect.appName)
                                root.removeActiveNotification(notifRect.notifId)
                            }
                        }

                        // Close button
                        Text {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            text: "󰅖"
                            color: "#888888"
                            font.family: "JetBrains Mono Nerd Font"
                            font.pixelSize: 12

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.removeActiveNotification(notifRect.notifId)
                            }
                        }
                    }
                }
            }
        }
    }

    // === PROCESSES FOR DATA COLLECTION ===

    // Clock timer (uses formatTime helper for consistent formatting)
    Timer {
        id: clockTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.currentTime = root.formatTime()
        Component.onCompleted: root.currentTime = root.formatTime()
    }

    // Audio volume process (using wpctl for Pipewire/PulseAudio)
    Process {
        id: volumeProc
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo 'Volume: 50%'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let output = this.text.trim()
                if (output.includes("MUTED")) {
                    root.audioMuted = true
                } else {
                    root.audioMuted = false
                }
                // Parse volume value (wpctl returns "Volume: 0.XX [MUTED]")
                let match = output.match(/(\d+\.?\d*)/)
                if (match) {
                    let vol = parseFloat(match[1])
                    // wpctl returns 0.0-1.0
                    if (vol <= 1.5) {
                        root.audioVolume = Math.round(vol * 100)
                    } else {
                        root.audioVolume = Math.round(vol)
                    }
                }
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: volumeProc.running = true
    }

    // Network status process
    Process {
        id: networkProc
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE,CONNECTION device 2>/dev/null | grep -E '^(wifi|ethernet)' | head -1 || echo 'disconnected'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let output = this.text.trim()
                if (output.includes("wifi") && output.includes("connected")) {
                    root.networkStatus = "wifi"
                    root.networkIcon = "󰤨"
                } else if (output.includes("ethernet") && output.includes("connected")) {
                    root.networkStatus = "ethernet"
                    root.networkIcon = "󰈀"
                } else {
                    root.networkStatus = "disconnected"
                    root.networkIcon = "󰤭"
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: networkProc.running = true
    }

    // Bluetooth status process
    Process {
        id: bluetoothProc
        command: ["sh", "-c", "bluetoothctl show 2>/dev/null | grep 'Powered' || echo 'Powered: no'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let output = this.text.trim()
                root.bluetoothEnabled = output.includes("Powered: yes")
            }
        }
    }

    // Bluetooth connected devices check
    Process {
        id: bluetoothConnectedProc
        command: ["sh", "-c", "bluetoothctl devices Connected 2>/dev/null | wc -l || echo '0'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let count = parseInt(this.text.trim())
                root.bluetoothConnected = count > 0
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            bluetoothProc.running = true
            bluetoothConnectedProc.running = true
        }
    }

    // Toggle bluetooth process (handles both rfkill and bluetoothctl)
    Process {
        id: toggleBluetoothProc
        command: ["sh", "-c", "if bluetoothctl show | grep -q 'Powered: yes'; then bluetoothctl power off && rfkill block bluetooth; else rfkill unblock bluetooth && sleep 0.5 && bluetoothctl power on; fi"]
        running: false
        onRunningChanged: if (!running) {
            bluetoothProc.running = true
            bluetoothConnectedProc.running = true
        }
    }

    // Battery status process
    Process {
        id: batteryProc
        command: ["sh", "-c", "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1 || echo '100'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let percent = parseInt(this.text.trim())
                if (!isNaN(percent)) {
                    root.batteryPercent = percent
                }
            }
        }
    }

    Process {
        id: batteryChargingProc
        command: ["sh", "-c", "cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1 || echo 'Unknown'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.batteryCharging = this.text.trim() === "Charging"
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            batteryProc.running = true
            batteryChargingProc.running = true
        }
    }

    // === CONTROL CENTER PROCESSES ===

    // Toggle mute process
    Process {
        id: toggleMuteProc
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        running: false
        onRunningChanged: if (!running) volumeProc.running = true
    }

    // Set volume process
    Process {
        id: setVolumeProc
        running: false
        onRunningChanged: if (!running) volumeProc.running = true
    }

    // Toggle WiFi process
    Process {
        id: toggleWifiProc
        command: ["sh", "-c", "nmcli radio wifi | grep -q enabled && nmcli radio wifi off || nmcli radio wifi on"]
        running: false
        onRunningChanged: if (!running) networkProc.running = true
    }

    // Battery time remaining process
    Process {
        id: batteryTimeProc
        command: ["sh", "-c", "upower -i $(upower -e | grep BAT) 2>/dev/null | grep 'time to' | awk '{print $4, $5}' || echo ''"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.batteryTimeRemaining = this.text.trim()
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: batteryTimeProc.running = true
    }

    // === SYSTEM INFO PROCESSES ===

    // CPU usage process
    Process {
        id: cpuUsageProc
        command: ["sh", "-c", "top -bn1 | grep 'Cpu(s)' | awk '{print int($2 + $4)}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let usage = parseInt(this.text.trim())
                if (!isNaN(usage)) root.cpuUsage = usage
            }
        }
    }

    // CPU temperature process
    Process {
        id: cpuTempProc
        command: ["sh", "-c", "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1 | awk '{print int($1/1000)}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let temp = parseInt(this.text.trim())
                if (!isNaN(temp)) root.cpuTemp = temp
            }
        }
    }

    // RAM usage process
    Process {
        id: ramUsageProc
        command: ["sh", "-c", "free | awk '/Mem:/ {printf \"%.0f\", $3/$2 * 100}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let usage = parseInt(this.text.trim())
                if (!isNaN(usage)) root.ramUsage = usage
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            cpuUsageProc.running = true
            cpuTempProc.running = true
            ramUsageProc.running = true
        }
    }

    // Power profile processes
    Process {
        id: getPowerProfileProc
        command: ["powerprofilesctl", "get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let profile = this.text.trim()
                // Only update if we got a valid response (powerprofilesctl is installed)
                if (profile === "power-saver") root.powerProfile = "Power Saver"
                else if (profile === "performance") root.powerProfile = "Performance"
                else if (profile === "balanced") root.powerProfile = "Balanced"
                // If empty or unknown, keep current value (don't reset to Balanced)
            }
        }
    }

    Process {
        id: setPowerProfileProc
        running: false
        // Don't auto-refresh after setting - trust the UI state
    }

    // Shutdown process
    Process {
        id: shutdownProc
        command: ["systemctl", "poweroff"]
        running: false
    }

    Process {
        id: lockProc
        command: ["hyprlock"]
        running: false
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: getPowerProfileProc.running = true
    }

    // Launcher IPC handler for Hyprland global shortcut
    // Usage in hyprland.conf: bind = SUPER, D, global, quickshell:launcher:toggle
    IpcHandler {
        target: "launcher"

        function toggle() {
            root.launcherVisible = !root.launcherVisible
            if (!root.launcherVisible) {
                root.launcherQuery = ""
                root.launcherResults = []
                root.launcherSelectedIndex = 0
                root.launcherCompletionMode = false
                root.launcherOriginalQuery = ""
            }
        }

        function show() {
            root.launcherVisible = true
        }

        function hide() {
            root.launcherVisible = false
            root.launcherQuery = ""
            root.launcherResults = []
            root.launcherSelectedIndex = 0
            root.launcherCompletionMode = false
            root.launcherOriginalQuery = ""
        }
    }

    // Global shortcut for Hyprland
    // Usage in hyprland.conf: bind = SUPER, D, global, quickshell:launcher
    GlobalShortcut {
        name: "launcher"
        description: "Toggle application launcher"

        onPressed: {
            root.launcherVisible = !root.launcherVisible
            if (!root.launcherVisible) {
                root.launcherQuery = ""
                root.launcherResults = []
                root.launcherSelectedIndex = 0
                root.launcherCompletionMode = false
                root.launcherOriginalQuery = ""
            }
        }
    }
}
