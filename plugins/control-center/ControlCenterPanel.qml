import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "Delight"

// Control Center panel: a layer-shell card under the bar, top-right, hosting
// ControlCenterView. Kept loaded so opening is a visibility flip, not a load.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  readonly property string pluginId: "delight.control-center"
  property alias store: statusStore
  property alias actions: commands
  property alias view: content

  function open(payloadJson) {
    let payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) { payload = {} }
    content.showInstall = payload.view === "install"
    opened = true
    statusStore.refresh()
    catalog.refresh()
    Qt.callLater(function() { content.focusFirst() })
  }

  function close() {
    opened = false
    content.showInstall = false
    content.toast.hide()
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  StatusStore { id: statusStore }

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

  // qmllint's Quickshell type info marks PanelWindow uncreatable; the shell creates it fine.
  // qmllint disable uncreatable-type missing-property
  PanelWindow {
    id: window
    visible: root.opened
    color: "transparent"
    anchors { top: true; right: true }
    margins { top: Style.space(6); right: Style.space(8) }
    exclusionMode: ExclusionMode.Normal
    implicitWidth: content.implicitWidth + Tokens.paddingLarge * 2
    implicitHeight: content.implicitHeight + Tokens.paddingLarge * 2
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "delight-control-center"
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    HyprlandFocusGrab {
      active: root.opened
      windows: [window]
      onCleared: root.requestClose()
    }

    ControlCenterView {
      id: content
      x: Tokens.paddingLarge
      y: Tokens.paddingLarge
      width: Tokens.sheetWidth
      height: implicitHeight
      focus: true
      toggles: statusStore.toggles
      rows: statusStore.rows
      devices: catalog.devices
      available: catalog.available
      opacity: root.opened ? 1 : 0
      transform: Translate { y: root.opened ? 0 : -Tokens.spacing }
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
    }
  }
}
