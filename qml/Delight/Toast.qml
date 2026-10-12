import QtQuick

// Quiet in-surface confirmation. Anchor it inside a sheet/panel and call
// show("Sent to Pixel", "󰄬") — it fades in, waits `timeout` ms, fades out.
// kind: "info" | "success" | "error". Errors stay until dismissed or replaced.
Item {
  id: root

  property string text: ""
  property string icon: ""
  property string kind: "info"
  property int timeout: 2600
  property bool shown: false

  function show(message, glyph, toastKind) {
    text = message
    icon = glyph || ""
    kind = toastKind || "info"
    shown = true
    if (kind === "error") timer.stop()
    else timer.restart()
  }

  function hide() {
    shown = false
  }

  implicitWidth: Math.min(Tokens.sheetWidth, pill.width)
  implicitHeight: pill.height
  visible: opacity > 0
  opacity: shown ? 1 : 0
  Accessible.role: Accessible.AlertMessage
  Accessible.name: text

  Behavior on opacity { NumberAnimation { duration: Tokens.animationNormal } }

  Timer {
    id: timer
    interval: root.timeout
    onTriggered: root.shown = false
  }

  Rectangle {
    id: pill
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(Tokens.sheetWidth, row.implicitWidth + Tokens.padding * 2)
    height: Tokens.controlHeight + 4
    radius: height / 2
    y: root.shown ? 0 : Tokens.spacing
    color: Tokens.surfaceRaised
    border.width: Tokens.borderWidth
    border.color: root.kind === "error" ? Tokens.urgent : Tokens.border

    Behavior on y { NumberAnimation { duration: Tokens.animationNormal; easing.type: Tokens.easing } }

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Tokens.spacingSmall

      Glyph {
        anchors.verticalCenter: parent.verticalCenter
        glyph: root.icon !== "" ? root.icon : root.kind === "error" ? "󰅚" : root.kind === "success" ? "󰄬" : "󰋽"
        size: Tokens.iconSizeSmall
        color: root.kind === "error" ? Tokens.urgent : Tokens.accent
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        elide: Text.ElideRight
        width: Math.min(implicitWidth, Tokens.sheetWidth - Tokens.padding * 4)
        color: Tokens.foreground
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSizeSmall
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.hide()
    }
  }
}
