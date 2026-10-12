pragma ComponentBehavior: Bound

import QtQuick

// One device from a `devices --json` provider: {id,name,kind,transport,
// connected,rssi?,mac?}. Set `device`, or the individual properties.
// `orientation: "chip"` renders a compact pill for horizontal strips.
Item {
  id: root

  property var device: ({})
  property string name: device && device.name ? device.name : (device && device.id ? device.id : "")
  property string kind: device && device.kind ? device.kind : ""
  property string transport: device && device.transport ? device.transport : ""
  property bool connected: !!(device && device.connected)
  property var rssi: device && device.rssi !== undefined ? device.rssi : null
  property string orientation: "row"
  property bool busy: false

  signal activated()

  readonly property bool chip: orientation === "chip"
  // 0..4 bars from dBm; -1 when unknown.
  readonly property int bars: rssi === null || rssi === undefined ? -1
    : rssi >= -55 ? 4 : rssi >= -67 ? 3 : rssi >= -78 ? 2 : rssi >= -90 ? 1 : 0
  readonly property string transportLabel: {
    switch (transport) {
    case "bluetooth": return "Bluetooth"
    case "wifi": return "Wi-Fi"
    case "lan": return "Local network"
    case "tailscale": return "Tailscale"
    case "usb": return "USB"
    default: return transport
    }
  }
  readonly property string detail: (connected ? "Connected" : "Not connected") + (transportLabel !== "" ? " · " + transportLabel : "")

  implicitWidth: chip ? chipRow.implicitWidth + Tokens.padding * 2 : Tokens.sheetWidth
  implicitHeight: chip ? Tokens.controlHeight + 6 : Tokens.rowHeight
  activeFocusOnTab: true

  Accessible.role: Accessible.Button
  Accessible.name: name
  Accessible.description: detail
  Accessible.onPressAction: root.activated()

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.activated()
      event.accepted = true
    }
  }

  Rectangle {
    id: bg
    anchors.fill: parent
    radius: root.chip ? height / 2 : Tokens.radiusSmall
    color: root.chip
      ? (root.connected ? Tokens.alpha(Tokens.accent, area.containsMouse ? 0.3 : 0.2) : area.containsMouse ? Tokens.surfacePressed : Tokens.surfaceRaised)
      : (area.containsMouse ? Tokens.surfaceRaised : "transparent")
    border.width: root.chip ? Tokens.borderWidth : 0
    border.color: root.connected ? Tokens.alpha(Tokens.accent, 0.5) : Tokens.border
    Behavior on color { ColorAnimation { duration: Tokens.animationFast } }
    FocusRing { radius_: bg.radius; shown: root.activeFocus }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  Row {
    id: chipRow
    visible: root.chip
    anchors.centerIn: parent
    spacing: Tokens.spacingSmall

    Glyph {
      anchors.verticalCenter: parent.verticalCenter
      glyph: Tokens.kindIcon(root.kind)
      size: Tokens.iconSizeSmall
      color: root.connected ? Tokens.accent : Tokens.foreground
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.name
      color: Tokens.foreground
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSizeSmall
      elide: Text.ElideRight
      width: Math.min(implicitWidth, 140)
    }
    Spinner { visible: root.busy; anchors.verticalCenter: parent.verticalCenter }
  }

  Item {
    visible: !root.chip
    anchors.fill: parent

    Rectangle {
      id: badge
      anchors.left: parent.left
      anchors.leftMargin: Tokens.spacing
      anchors.verticalCenter: parent.verticalCenter
      width: Math.round(Tokens.badgeSize * 0.85)
      height: width
      radius: width / 2
      color: root.connected ? Tokens.accent : Tokens.surfacePressed

      Glyph {
        anchors.centerIn: parent
        glyph: Tokens.kindIcon(root.kind)
        size: Tokens.iconSizeSmall
        color: root.connected ? Tokens.accentInk : Tokens.foreground
      }
    }

    Column {
      anchors.left: badge.right
      anchors.leftMargin: Tokens.spacingLarge - 2
      anchors.right: signalBars.left
      anchors.rightMargin: Tokens.spacing
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1

      Text {
        width: parent.width
        text: root.name
        elide: Text.ElideRight
        color: Tokens.foreground
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSize
      }
      Text {
        width: parent.width
        text: root.detail
        elide: Text.ElideRight
        color: Tokens.muted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSizeSmall
      }
    }

    Row {
      id: signalBars
      anchors.right: parent.right
      anchors.rightMargin: Tokens.padding
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2
      visible: root.bars >= 0 || root.busy

      Spinner { visible: root.busy; anchors.verticalCenter: parent.verticalCenter }

      Repeater {
        model: root.bars >= 0 ? 4 : 0
        delegate: Rectangle {
          required property int index
          width: 3
          height: 4 + index * 3
          radius: 1
          anchors.bottom: parent.bottom
          color: index < root.bars ? Tokens.foreground : Tokens.alpha(Tokens.foreground, 0.2)
        }
      }
    }
  }
}
