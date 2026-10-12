pragma ComponentBehavior: Bound

import QtQuick
import "Delight"

// Control Center content, independent of the window that hosts it.
// Large tiles for toggleable modules, compact rows for the rest, a device
// strip, and an install list when nothing (or not everything) is installed.
// Keys: Tab/arrows/hjkl move, Space/Enter activate, "." opens "…", Esc closes.
FocusScope {
  id: root

  property var toggles: []
  property var rows: []
  property var devices: []
  property var available: []
  property bool showInstall: false
  readonly property bool empty: toggles.length === 0 && rows.length === 0
  readonly property bool installVisible: empty || showInstall
  property alias toast: toast

  signal toggleRequested(var status)
  signal detailRequested(var status)
  signal deviceActivated(var device)
  signal installRequested(string id)
  signal closeRequested()

  implicitWidth: sheet.implicitWidth
  implicitHeight: sheet.implicitHeight

  function focusFirst() {
    let first = tileRepeater.count > 0 ? tileRepeater.itemAt(0)
      : rowRepeater.count > 0 ? rowRepeater.itemAt(0)
      : installRepeater.count > 0 ? installRepeater.itemAt(0) : footerButton
    if (first) first.forceActiveFocus()
  }

  function focusables() {
    let out = []
    let i
    for (i = 0; i < tileRepeater.count; i++) out.push(tileRepeater.itemAt(i))
    for (i = 0; i < rowRepeater.count; i++) out.push(rowRepeater.itemAt(i))
    for (i = 0; i < deviceRepeater.count; i++) out.push(deviceRepeater.itemAt(i))
    if (root.installVisible) for (i = 0; i < installRepeater.count; i++) out.push(installRepeater.itemAt(i))
    if (footerButton.visible) out.push(footerButton)
    return out.filter(function(item) { return item && item.visible })
  }

  // Grid-aware movement: tiles sit in two columns, everything else is a list.
  function moveFocus(dx, dy) {
    let items = focusables()
    if (items.length === 0) return
    let current = -1
    for (let i = 0; i < items.length; i++) if (items[i].activeFocus) current = i
    if (current < 0) { items[0].forceActiveFocus(); return }
    let tiles = tileRepeater.count
    let next = current
    if (current < tiles) {
      next = dy !== 0 ? current + dy * 2 : current + dx
      if (dy > 0 && next >= tiles) next = tiles
      if (next < 0) next = current
    } else {
      next = current + (dy !== 0 ? dy : dx)
      if (dy < 0 && next < tiles && next >= 0) next = Math.max(0, tiles - (tiles % 2 === 0 ? 2 : 1))
    }
    next = Math.max(0, Math.min(items.length - 1, next))
    items[next].forceActiveFocus()
  }

  Keys.onPressed: event => {
    let k = event.key
    if (k === Qt.Key_Escape) root.closeRequested()
    else if (k === Qt.Key_Left || k === Qt.Key_H) root.moveFocus(-1, 0)
    else if (k === Qt.Key_Right || k === Qt.Key_L) root.moveFocus(1, 0)
    else if (k === Qt.Key_Up || k === Qt.Key_K) root.moveFocus(0, -1)
    else if (k === Qt.Key_Down || k === Qt.Key_J) root.moveFocus(0, 1)
    else return
    event.accepted = true
  }

  Sheet {
    id: sheet
    anchors.fill: parent
    title: root.installVisible && root.empty ? "Omarchy Delight" : ""
    subtitle: root.installVisible && root.empty ? "No features installed yet" : ""
    icon: root.installVisible && root.empty ? "󰘮" : ""
    closeOnEscape: false

    // ---- large tiles
    Flow {
      id: tileGrid
      width: parent.width
      spacing: Tokens.spacing
      visible: tileRepeater.count > 0

      Repeater {
        id: tileRepeater
        model: root.toggles
        delegate: Tile {
          required property var modelData
          required property int index
          // A lone last tile spans the row instead of leaving a hole.
          width: index === tileRepeater.count - 1 && tileRepeater.count % 2 === 1
            ? tileGrid.width : (tileGrid.width - tileGrid.spacing) / 2
          icon: modelData.icon
          title: modelData.title
          subtitle: modelData.subtitle
          status: modelData.state
          reason: modelData.reason
          toggleable: true
          hasDetail: true
          detailLabel: modelData.actions.length > 0 ? modelData.actions[0].label : "Open " + modelData.title
          onToggled: root.toggleRequested(modelData)
          onDetailRequested: root.detailRequested(modelData)
          onExplainRequested: toast.show(modelData.reason, modelData.icon, "info")
        }
      }
    }

    // ---- compact rows
    Rectangle {
      width: parent.width
      height: rowColumn.implicitHeight + Tokens.spacingXs * 2
      visible: rowRepeater.count > 0
      radius: Tokens.radius
      color: Tokens.surface
      border.width: Tokens.borderWidth
      border.color: Tokens.divider

      Column {
        id: rowColumn
        anchors.fill: parent
        anchors.margins: Tokens.spacingXs

        Repeater {
          id: rowRepeater
          model: root.rows
          delegate: Tile {
            required property var modelData
            width: rowColumn.width
            compact: true
            icon: modelData.icon
            title: modelData.title
            subtitle: modelData.subtitle
            status: modelData.state
            reason: modelData.reason
            toggleable: false
            hasDetail: true
            setupLabel: modelData.state === "needs-setup" ? "Set up" : modelData.state === "error" ? "Fix" : ""
            detailLabel: modelData.actions.length > 0 ? modelData.actions[0].label : "Open " + modelData.title
            onDetailRequested: root.detailRequested(modelData)
            onExplainRequested: toast.show(modelData.reason, modelData.icon, "info")
          }
        }
      }
    }

    // ---- device strip
    Column {
      width: parent.width
      spacing: Tokens.spacingSmall
      visible: deviceRepeater.count > 0

      Text {
        text: "Devices"
        color: Tokens.muted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSizeCaption
        font.weight: Font.DemiBold
        leftPadding: Tokens.spacingXs
      }

      Flickable {
        id: strip
        width: parent.width
        height: deviceRow.height + Tokens.focusWidth * 4
        contentWidth: deviceRow.width + Tokens.focusWidth * 4
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        Row {
          id: deviceRow
          x: Tokens.focusWidth * 2
          y: Tokens.focusWidth * 2
          spacing: Tokens.spacingSmall

          Repeater {
            id: deviceRepeater
            model: root.devices
            delegate: DeviceRow {
              required property var modelData
              device: modelData
              orientation: "chip"
              onActivated: root.deviceActivated(modelData)
              onActiveFocusChanged: if (activeFocus) {
                if (x + width > strip.contentX + strip.width) strip.contentX = x + width - strip.width + Tokens.focusWidth * 4
                else if (x < strip.contentX) strip.contentX = x
              }
            }
          }
        }
      }
    }

    // ---- install list / empty state
    Column {
      width: parent.width
      spacing: Tokens.spacingXs
      visible: root.installVisible

      Text {
        width: parent.width
        text: root.available.length > 0
          ? (root.empty ? "Pick a feature to get started. Each one installs its own packages and can be removed again." : "Available features")
          : "Every Delight feature is installed."
        wrapMode: Text.Wrap
        color: Tokens.muted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSizeSmall
        leftPadding: Tokens.spacingXs
        bottomPadding: Tokens.spacingXs
      }

      Repeater {
        id: installRepeater
        model: root.available
        delegate: ListRow {
          id: installRow
          required property var modelData
          width: parent.width
          icon: "󰏗"
          title: modelData.name
          subtitle: "delight " + modelData.id + " install"
          onActivated: root.installRequested(modelData.id)

          Button {
            text: "Install"
            variant: "primary"
            activeFocusOnTab: false
            onClicked: root.installRequested(installRow.modelData.id)
          }
        }
      }
    }

    // ---- footer
    Item {
      width: parent.width
      height: footerButton.height
      visible: footerButton.visible

      Button {
        id: footerButton
        anchors.right: parent.right
        visible: !root.empty
        variant: "plain"
        icon: root.showInstall ? "󰅃" : "󰐕"
        text: root.showInstall ? "Done" : "Install features…"
        onClicked: root.showInstall = !root.showInstall
      }
    }
  }

  Toast {
    id: toast
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Tokens.padding
  }
}
