pragma ComponentBehavior: Bound

import QtQuick
import "../../Delight"

// Every qml/Delight component on one board, for docs/design.md screenshots.
Item {
  id: root

  property string wallpaper: ""

  Rectangle { anchors.fill: parent; color: Tokens.background }
  Image { anchors.fill: parent; source: root.wallpaper; fillMode: Image.PreserveAspectCrop; opacity: 0.5 }

  Row {
    anchors.centerIn: parent
    spacing: 20

    Sheet {
      width: 400
      title: "Tiles"
      subtitle: "Tile · large and compact"

      Grid {
        id: grid
        columns: 2
        spacing: Tokens.spacing
        width: parent.width
        Repeater {
          model: [["on", "AirPlay", "Receiving as Desk", "󰑈"], ["off", "Control", "Off", "󰍽"],
                  ["busy", "Drop", "Receiving…", "󰀂"], ["needs-setup", "Hotspot", "Pair a phone first", "󰀃"],
                  ["unsupported", "Sidecar", "No spare display", "󰍹"], ["error", "Camera", "Driver failed", "󰄀"]]
          delegate: Tile {
            required property var modelData
            width: (grid.width - grid.spacing) / 2
            status: modelData[0]
            title: modelData[1]
            subtitle: modelData[2]
            reason: modelData[2]
            icon: modelData[3]
            hasDetail: true
          }
        }
      }
      Tile { width: parent.width; compact: true; toggleable: false; hasDetail: true; status: "off"; title: "Sync"; subtitle: "Last synced 10 min ago"; icon: "󰓦" }
      Tile { width: parent.width; compact: true; toggleable: false; hasDetail: true; status: "error"; title: "Camera"; reason: "v4l2loopback failed"; icon: "󰄀" }
    }

    Column {
      spacing: 20

      Sheet {
        width: 340
        title: "Controls"
        subtitle: "Button · Toggle · ProgressRing · Toast"
        icon: "󰘮"
        showClose: true

        Row {
          spacing: Tokens.spacing
          Button { text: "Send"; variant: "primary" }
          Button { text: "Cancel" }
          Button { text: "Forget"; variant: "destructive" }
          Button { icon: "󰐕"; label: "Add" }
        }
        Toggle { width: parent.width; text: "Receive from everyone"; description: "For 10 minutes"; checked: true }
        Toggle { width: parent.width; text: "Keep awake while sharing" }
        Row {
          spacing: Tokens.spacingLarge
          ProgressRing { value: 0.25; label: "25%" }
          ProgressRing { value: 0.7; label: "70%" }
          ProgressRing { indeterminate: true }
          Spinner { anchors.verticalCenter: parent.verticalCenter }
        }
        Item {
          width: parent.width
          height: toast.height
          Toast { id: toast; timeout: 600000; anchors.horizontalCenter: parent.horizontalCenter; Component.onCompleted: show("Sent 2 files to Pixel 9", "", "success") }
        }
      }

      Sheet {
        width: 340
        title: "Devices"
        subtitle: "DeviceRow · row and chip"

        DeviceRow { width: parent.width; device: ({ name: "Pixel 9", kind: "phone", transport: "bluetooth", connected: true, rssi: -52 }) }
        DeviceRow { width: parent.width; device: ({ name: "iPad Air", kind: "tablet", transport: "wifi", connected: false, rssi: -74 }) }
        Row {
          spacing: Tokens.spacingSmall
          DeviceRow { orientation: "chip"; device: ({ name: "Living Room TV", kind: "tv", transport: "lan", connected: false }) }
          DeviceRow { orientation: "chip"; device: ({ name: "Buds", kind: "headphones", connected: true }) }
        }
      }
    }

    Column {
      spacing: 20

      Sheet {
        width: 340
        title: "Share"
        subtitle: "TargetGrid"
        icon: "󰀂"

        TargetGrid {
          width: parent.width
          columns: 4
          activeTargetId: "pixel"
          activeProgress: 0.6
          targets: [{ id: "pixel", label: "Pixel 9", kind: "phone" }, { id: "ipad", label: "iPad Air", kind: "tablet" },
                    { id: "desk", label: "Desk", kind: "computer" }, { id: "clip", label: "Clipboard", kind: "clipboard" }]
        }
      }

      Sheet {
        width: 340
        title: "Pair"
        subtitle: "QrView"

        QrView {
          anchors.horizontalCenter: parent.horizontalCenter
          size: 140
          text: "https://github.com/hiresello/omarchy-delight"
          caption: "Scan with your phone to pair"
        }
      }
    }
  }
}
