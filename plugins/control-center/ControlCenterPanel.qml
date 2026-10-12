pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "Delight"

// Control Center panel: a layer-shell card under the bar, top-right, hosting
// ControlCenterView. Kept loaded so opening is a visibility flip, not a load.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  // When an outside click last closed us; the bar click that caused it must
  // not reopen the panel it just dismissed.
  property real dismissedAt: 0
  // Card's distance from the screen's right edge; beneath the bar icon when
  // the bar opened us, else the window gap.
  property int rightInset: Tokens.edgeGap
  // Exclusive focus makes Hyprland send every pointer event to the card, so the
  // dismiss layers would never see a click. Hold it briefly to take focus on
  // open (as upstream KeyboardPanel does), then settle on OnDemand.
  property bool focusPrimed: false
  readonly property string pluginId: "delight.control-center"
  property alias store: statusStore
  property alias actions: commands
  property alias view: content

  function open(payloadJson) {
    let payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) { payload = {} }
    if (Date.now() - dismissedAt < 350) {
      requestClose()
      return
    }
    Tokens.refresh()
    let centred = payload.anchorX > 0 && payload.barWidth > 0
      ? Math.round(payload.barWidth - payload.anchorX - Tokens.sheetWidth / 2) : 0
    rightInset = Math.max(Tokens.edgeGap, centred)
    content.showInstall = payload.view === "install"
    focusPrimed = false
    opened = true
    if (window.backingWindowVisible) focusPrimeTimer.restart()
    statusStore.refresh()
    catalog.refresh()
    Qt.callLater(function() { content.focusFirst() })
  }

  function close() {
    opened = false
    focusPrimed = false
    content.showInstall = false
    content.toast.hide()
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  StatusStore {
    id: statusStore
    live: root.opened
  }

  Catalog {
    id: catalog
    active: root.opened
  }

  Actions {
    id: commands
    // Status files land within a few ms of a toggle; poll once in case not.
    onRan: refreshSoon.restart()
  }

  Timer {
    id: refreshSoon
    interval: 600
    onTriggered: statusStore.refresh()
  }

  // Outside-click dismissal: while open, a transparent full-screen layer on
  // every output closes the panel on any press. It sits on the Top layer, above
  // windows and (mapped later) the bar, so clicking the bar icon again closes
  // rather than re-toggles; the card is on Overlay, always above it. The
  // namespace avoids the "^delight-" blur rule so it costs no blur pass.
  // qmllint's Quickshell type info marks PanelWindow uncreatable; the shell creates it fine.
  // qmllint disable uncreatable-type missing-property
  Variants {
    model: Quickshell.screens
    delegate: PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.opened
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.namespace: "control-center-dismiss-delight"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: {
          root.dismissedAt = Date.now()
          root.requestClose()
        }
      }
    }
  }

  PanelWindow {
    id: window
    visible: root.opened
    color: "transparent"
    anchors { top: true; right: true }
    // The card lines up with window gaps (or the bar icon). The surface adds
    // shadowMargin around it for the baked shadow, but never past the screen
    // edge, where a layer would be cropped.
    readonly property int rightMargin: Math.max(0, root.rightInset - Tokens.shadowMargin)
    readonly property int innerRight: root.rightInset - rightMargin
    margins { top: Tokens.edgeGap - Tokens.shadowMargin; right: window.rightMargin }
    exclusionMode: ExclusionMode.Normal
    implicitWidth: Tokens.shadowMargin + content.implicitWidth + window.innerRight
    implicitHeight: content.implicitHeight + Tokens.shadowMargin * 2
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "delight-control-center"
    WlrLayershell.keyboardFocus: root.opened
      ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None
    onBackingWindowVisibleChanged: if (root.opened && backingWindowVisible) focusPrimeTimer.restart()

    Timer {
      id: focusPrimeTimer
      interval: 75
      onTriggered: if (root.opened) root.focusPrimed = true
    }

    ControlCenterView {
      id: content
      x: Tokens.shadowMargin
      y: Tokens.shadowMargin
      width: Tokens.sheetWidth
      height: implicitHeight
      focus: true
      toggles: statusStore.toggles
      rows: statusStore.rows
      devices: catalog.devices
      available: catalog.available
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.96
      transformOrigin: Item.TopRight
      onToggleRequested: status => commands.toggle(status)
      onDetailRequested: status => {
        commands.detail(status)
        root.requestClose()
      }
      onDeviceActivated: device => {
        commands.openDevice(device)
        root.requestClose()
      }
      onInstallRequested: id => {
        commands.install(id)
        root.requestClose()
      }
      onCloseRequested: root.requestClose()

      Behavior on opacity { NumberAnimation { duration: Tokens.animationFast; easing.type: Tokens.easing } }
      Behavior on scale { NumberAnimation { duration: Tokens.animationNormal; easing.type: Tokens.easingSpring } }
    }
  }
}
