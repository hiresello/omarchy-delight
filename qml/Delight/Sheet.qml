import QtQuick

// Rounded, theme-aware card for Delight panels and modals. Children stack in a
// column under an optional header (icon, title, subtitle, close button).
// Esc emits closeRequested() while anything inside the sheet has focus; place
// it in a SheetWindow for a centred modal. The material is static glass: tint,
// sheen, a bright top rim and a baked shadow (room for it: Tokens.shadowMargin).
Rectangle {
  id: root

  property string title: ""
  property string subtitle: ""
  property string icon: ""
  property bool showClose: false
  property bool closeOnEscape: true
  property bool shadow: true
  default property alias content: body.data
  // Extra header controls, right-aligned before the close button.
  property alias headerActions: actions.data

  signal closeRequested()

  implicitWidth: Tokens.sheetWidth
  implicitHeight: column.implicitHeight + Tokens.paddingLarge * 2
  radius: Tokens.radiusLarge
  color: Tokens.sheetBackground
  border.color: Tokens.sheetBorder
  border.width: Tokens.borderWidth

  Behavior on color { ColorAnimation { duration: Tokens.animationNormal } }

  BorderImage {
    z: -1
    visible: root.shadow
    anchors.fill: parent
    anchors.margins: -Tokens.shadowMargin
    source: Qt.resolvedUrl("assets/shadow.png")
    border { left: 56; top: 56; right: 56; bottom: 56 }
    opacity: Tokens.dark ? 1 : 0.6
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: root.border.width
    radius: Math.max(0, root.radius - root.border.width)
    gradient: Gradient {
      GradientStop { position: 0; color: Tokens.glassSheen }
      GradientStop { position: 0.45; color: "transparent" }
    }
  }

  Rectangle {
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    width: parent.width - root.radius * 1.2
    height: 1
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: "transparent" }
      GradientStop { position: 0.5; color: Tokens.glassRim }
      GradientStop { position: 1; color: "transparent" }
    }
  }

  Keys.onEscapePressed: event => {
    if (!root.closeOnEscape) {
      event.accepted = false
      return
    }
    root.closeRequested()
    event.accepted = true
  }

  Column {
    id: column
    anchors.fill: parent
    anchors.margins: Tokens.paddingLarge
    spacing: Tokens.spacingLarge

    Item {
      id: header
      width: parent.width
      height: Math.max(heading.implicitHeight, closeButton.visible ? closeButton.height : 0, headerIcon.visible ? headerIcon.height : 0)
      visible: root.title !== "" || root.showClose || actions.children.length > 0

      Rectangle {
        id: headerIcon
        visible: root.icon !== ""
        width: Tokens.badgeSize
        height: width
        radius: width / 2
        color: Tokens.accent
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        Glyph {
          anchors.centerIn: parent
          glyph: root.icon
          color: Tokens.onAccent
        }
      }

      Column {
        id: heading
        anchors.left: headerIcon.visible ? headerIcon.right : parent.left
        anchors.leftMargin: headerIcon.visible ? Tokens.spacingLarge : 0
        anchors.right: actions.left
        anchors.rightMargin: Tokens.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
          width: parent.width
          text: root.title
          visible: text !== ""
          elide: Text.ElideRight
          color: Tokens.foreground
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSizeTitle
          font.weight: Font.DemiBold
          font.letterSpacing: Tokens.letterSpacingTitle
        }
        Text {
          width: parent.width
          text: root.subtitle
          visible: text !== ""
          elide: Text.ElideRight
          color: Tokens.muted
          font.family: Tokens.fontFamily
          font.pixelSize: Tokens.fontSizeSmall
        }
      }

      Row {
        id: actions
        anchors.right: closeButton.visible ? closeButton.left : parent.right
        anchors.rightMargin: closeButton.visible ? Tokens.spacing : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing
      }

      Button {
        id: closeButton
        visible: root.showClose
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        icon: "󰅖"
        label: "Close"
        variant: "plain"
        onClicked: root.closeRequested()
      }
    }

    Column {
      id: body
      width: parent.width
      spacing: Tokens.spacing
    }
  }
}
