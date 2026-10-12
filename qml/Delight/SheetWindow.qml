import QtQuick
import Quickshell
import Quickshell.Wayland

// Centred modal for module sheets: a scrimmed fullscreen layer surface holding
// a Sheet. Drive `shown`; Esc, the close button and clicks on the scrim emit
// closeRequested(). Children go into the sheet body.
// qmllint's Quickshell type info marks PanelWindow uncreatable; the shell creates it fine.
// qmllint disable uncreatable-type missing-property
PanelWindow {
  id: window

  property bool shown: false
  property string title: ""
  property string subtitle: ""
  property string icon: ""
  property int sheetWidth: Tokens.sheetWidth
  property bool dismissOnScrim: true
  default property alias content: modal.content
  property alias sheet: modal

  signal closeRequested()

  visible: shown || fade.running
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "delight-sheet"
  WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  onShownChanged: if (shown) {
    Tokens.refresh()
    Qt.callLater(function() { modal.forceActiveFocus() })
  }

  Rectangle {
    id: scrim
    anchors.fill: parent
    color: Tokens.scrim
    opacity: window.shown ? 1 : 0

    Behavior on opacity { NumberAnimation { id: fade; duration: Tokens.animationNormal } }

    MouseArea {
      anchors.fill: parent
      onClicked: if (window.dismissOnScrim) window.closeRequested()
    }
  }

  // Swallow clicks on the sheet so they do not reach the scrim.
  MouseArea { anchors.fill: modal }

  Sheet {
    id: modal
    anchors.centerIn: parent
    width: Math.min(window.sheetWidth, window.width - Tokens.paddingLarge * 2)
    title: window.title
    subtitle: window.subtitle
    icon: window.icon
    showClose: true
    focus: true
    opacity: scrim.opacity
    scale: window.shown ? 1 : 0.96
    onCloseRequested: window.closeRequested()

    Behavior on scale { NumberAnimation { duration: Tokens.animationNormal; easing.type: Tokens.easing } }
  }
}
