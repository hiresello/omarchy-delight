import QtQuick

// Keyboard focus outline. Place inside a control; it fills the parent.
Rectangle {
  id: root

  property bool shown: parent ? parent.activeFocus : false
  property real radius_: Tokens.radius

  anchors.fill: parent
  anchors.margins: -Tokens.focusWidth - 1
  radius: radius_ + Tokens.focusWidth + 1
  color: "transparent"
  border.width: Tokens.focusWidth
  border.color: Tokens.focusRing
  opacity: shown ? 1 : 0
  visible: opacity > 0

  Behavior on opacity { NumberAnimation { duration: Tokens.animationFast } }
}
