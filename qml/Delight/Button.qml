import QtQuick

// Delight push button. variant: "primary" | "secondary" | "plain" | "destructive".
// Pass `icon` alone for a round icon-only button (set `label` for accessibility).
Item {
  id: root

  property string text: ""
  property string icon: ""
  property string variant: "secondary"
  property string label: text
  property bool busy: false
  readonly property bool iconOnly: text === "" && icon !== ""
  readonly property bool hovered: area.containsMouse
  readonly property bool down: area.pressed

  signal clicked()

  implicitHeight: Tokens.controlHeight
  implicitWidth: iconOnly ? implicitHeight : Math.max(implicitHeight * 2, content.implicitWidth + Tokens.padding * 2)
  activeFocusOnTab: enabled
  opacity: enabled ? 1 : 0.45

  Accessible.role: Accessible.Button
  Accessible.name: root.label
  Accessible.onPressAction: root.activate()

  function activate() {
    if (enabled && !busy) clicked()
  }

  readonly property color fill: {
    if (variant === "primary") return Tokens.accent
    if (variant === "destructive") return Tokens.urgent
    if (variant === "plain") return "transparent"
    return Tokens.surfaceRaised
  }
  readonly property color ink: {
    if (variant === "primary") return Tokens.onAccent
    if (variant === "destructive") return Tokens.onUrgent
    return Tokens.foreground
  }

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.activate()
      event.accepted = true
    }
  }

  Rectangle {
    id: bg
    anchors.fill: parent
    radius: root.iconOnly ? height / 2 : Tokens.radiusSmall
    color: root.down ? Qt.darker(root.fill, 1.15)
      : root.hovered ? (root.variant === "plain" ? Tokens.surfaceRaised : Qt.lighter(root.fill, 1.12))
      : root.fill
    border.width: root.variant === "secondary" ? Tokens.borderWidth : 0
    border.color: Tokens.border
    scale: root.down ? 0.97 : 1

    Behavior on color { ColorAnimation { duration: Tokens.animationFast } }
    Behavior on scale { NumberAnimation { duration: Tokens.animationFast } }

    FocusRing { radius_: bg.radius; shown: root.activeFocus }
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Tokens.spacingSmall

    Spinner {
      visible: root.busy
      anchors.verticalCenter: parent.verticalCenter
      color: root.ink
    }
    Glyph {
      visible: root.icon !== "" && !root.busy
      anchors.verticalCenter: parent.verticalCenter
      glyph: root.icon
      size: Tokens.iconSizeSmall
      color: root.ink
    }
    Text {
      visible: root.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      color: root.ink
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSizeSmall
      font.weight: root.variant === "primary" ? Font.DemiBold : Font.Medium
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.activate()
  }
}
