import QtQuick

// Labelled switch. Controlled: emits toggled(next); bind `checked` to state.
Item {
  id: root

  property bool checked: false
  property string text: ""
  property string description: ""
  property bool busy: false
  readonly property bool hovered: area.containsMouse

  signal toggled(bool checked)

  implicitWidth: Math.max(labels.implicitWidth + track.width + Tokens.spacingLarge, 160)
  implicitHeight: Math.max(Tokens.controlHeight, labels.implicitHeight)
  activeFocusOnTab: enabled
  opacity: enabled ? 1 : 0.45

  Accessible.role: Accessible.CheckBox
  Accessible.name: root.text
  Accessible.checkable: true
  Accessible.checked: root.checked
  Accessible.onToggleAction: root.activate()
  Accessible.onPressAction: root.activate()

  function activate() {
    if (enabled && !busy) toggled(!checked)
  }

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.activate()
      event.accepted = true
    }
  }

  Column {
    id: labels
    anchors.left: parent.left
    anchors.right: track.left
    anchors.rightMargin: Tokens.spacingLarge
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    Text {
      width: parent.width
      text: root.text
      visible: text !== ""
      color: Tokens.foreground
      elide: Text.ElideRight
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSize
    }
    Text {
      width: parent.width
      text: root.description
      visible: text !== ""
      color: Tokens.muted
      wrapMode: Text.Wrap
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSizeSmall
    }
  }

  Rectangle {
    id: track
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Math.round(Tokens.controlHeight * 1.5)
    height: Math.round(Tokens.controlHeight * 0.8)
    radius: height / 2
    color: root.checked ? Tokens.accent : Tokens.surfacePressed
    border.width: root.checked ? 0 : Tokens.borderWidth
    border.color: Tokens.border

    Behavior on color { ColorAnimation { duration: Tokens.animationFast } }

    Rectangle {
      id: knob
      width: track.height - 4
      height: width
      radius: width / 2
      y: 2
      x: root.checked ? track.width - width - 2 : 2
      color: root.checked ? Tokens.accentInk : Tokens.foreground

      Behavior on x { NumberAnimation { duration: Tokens.animationNormal; easing.type: Tokens.easing } }

      Spinner {
        anchors.centerIn: parent
        visible: root.busy
        width: parent.width - 6
        height: width
        color: Tokens.accent
      }
    }

    FocusRing { radius_: track.radius; shown: root.activeFocus }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.activate()
  }
}
