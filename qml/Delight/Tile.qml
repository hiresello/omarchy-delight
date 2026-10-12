import QtQuick

// Control Center tile for one module status. Large (default) for toggleable
// modules; `compact: true` renders a slim row. Clicking the body emits
// toggled() when toggleable, otherwise detailRequested(); the chevron that
// appears on hover/focus and a right-click emit detailRequested(). Keyboard:
// Space/Enter = body, "." or Shift+Enter = details. A compact row with
// `setupLabel` shows that button instead of the chevron.
Item {
  id: root

  property string icon: ""
  property string title: ""
  property string subtitle: ""
  property string status: "off"
  property bool toggleable: true
  property bool hasDetail: false
  property string reason: ""
  property bool compact: false
  property string detailLabel: "More"
  property string setupLabel: ""

  signal toggled()
  signal detailRequested()
  // Activating an unsupported tile: show why instead of acting.
  signal explainRequested()

  readonly property bool active: status === "on"
  readonly property bool busy: status === "busy"
  readonly property bool unavailable: status === "unsupported"
  readonly property bool failed: status === "error"
  readonly property color activeColor: badge.color
  readonly property bool hovered: bodyArea.containsMouse || detailArea.containsMouse
  readonly property bool showChevron: hasDetail && setupLabel === "" && !unavailable && (hovered || activeFocus)
  // Reason wins over subtitle for states that must explain themselves.
  readonly property string caption: (unavailable || failed || status === "needs-setup") && reason !== ""
    ? reason : (subtitle !== "" ? subtitle : Tokens.stateLabel(status))

  implicitWidth: compact ? Tokens.sheetWidth : Math.round(Tokens.sheetWidth / 2)
  implicitHeight: compact ? Math.max(Tokens.rowHeight, labels.implicitHeight + Tokens.spacingLarge * 2) : Tokens.tileHeight
  activeFocusOnTab: true

  Accessible.role: toggleable ? Accessible.CheckBox : Accessible.Button
  Accessible.name: title
  Accessible.description: caption
  Accessible.checkable: toggleable
  Accessible.checked: active
  Accessible.onPressAction: root.activate()

  function activate() {
    if (unavailable) explainRequested()
    else if (toggleable && !busy) toggled()
    else if (!toggleable) detailRequested()
  }

  Keys.onPressed: event => {
    let detailKey = event.key === Qt.Key_Period || event.text === "." || event.key === Qt.Key_Menu
      || ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier))
    if (detailKey) {
      root.detailRequested()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.activate()
      event.accepted = true
    }
  }

  Rectangle {
    id: card
    anchors.fill: parent
    radius: root.compact ? Tokens.radiusSmall : Tokens.radius
    color: bodyArea.pressed ? Tokens.surfacePressed
      : root.compact ? (root.hovered ? Tokens.surface : "transparent")
      : root.hovered || root.active ? Tokens.surfaceRaised : Tokens.surface
    border.width: root.compact ? 0 : Tokens.borderWidth
    border.color: root.failed ? Tokens.alpha(Tokens.urgent, 0.6) : Tokens.border
    scale: bodyArea.pressed && !root.compact ? 0.97 : 1

    Behavior on color { ColorAnimation { duration: Tokens.animationFast } }
    Behavior on scale { NumberAnimation { duration: Tokens.animationFast; easing.type: Tokens.easing } }

    FocusRing { radius_: card.radius; shown: root.activeFocus }
  }

  // Round state badge: filled with the accent and a soft gloss when on.
  Rectangle {
    id: badge
    anchors.left: parent.left
    anchors.leftMargin: root.compact ? Tokens.spacing : Math.round((Tokens.tileHeight - Tokens.badgeSize) / 2)
    anchors.verticalCenter: parent.verticalCenter
    width: root.compact ? Tokens.badgeSize - Tokens.spacingXs : Tokens.badgeSize
    height: width
    radius: width / 2
    color: root.active ? Tokens.accent : root.failed ? Tokens.urgent : Tokens.stateColor(root.status)
    opacity: root.unavailable ? 0.55 : 1
    Behavior on color { ColorAnimation { duration: Tokens.animationNormal } }

    Rectangle {
      visible: root.active || root.failed
      anchors.fill: parent
      radius: parent.radius
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.30) }
        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.04) }
        GradientStop { position: 1; color: "transparent" }
      }
    }

    Glyph {
      anchors.centerIn: parent
      glyph: root.icon !== "" ? root.icon : "󰘔"
      size: root.compact ? Tokens.iconSizeSmall : Tokens.iconSize
      color: root.active ? Tokens.accentInk : root.failed ? Tokens.urgentInk : Tokens.foreground
    }

    ProgressRing {
      anchors.fill: parent
      anchors.margins: -3
      visible: root.busy
      indeterminate: true
      thickness: 2
    }
  }

  Column {
    id: labels
    anchors.left: badge.right
    anchors.leftMargin: root.compact ? Tokens.spacingLarge : Tokens.spacing + 2
    // Large tiles keep the full width for text; the chevron floats over it.
    anchors.right: root.compact ? trailing.left : parent.right
    anchors.rightMargin: root.compact ? Tokens.spacingSmall : Tokens.spacing
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1
    opacity: root.unavailable ? 0.7 : 1

    Text {
      width: parent.width
      text: root.title
      elide: Text.ElideRight
      color: Tokens.foreground
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSize
      font.weight: Font.DemiBold
    }
    Text {
      width: parent.width
      text: root.caption
      visible: text !== ""
      elide: Text.ElideRight
      wrapMode: root.compact ? Text.Wrap : Text.NoWrap
      maximumLineCount: root.compact ? 2 : 1
      color: root.failed ? Tokens.urgent : Tokens.muted
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSizeCaption
      font.features: { "tnum": 1 }
    }
  }

  Row {
    id: trailing
    anchors.right: parent.right
    anchors.rightMargin: Tokens.spacing
    anchors.verticalCenter: parent.verticalCenter
    spacing: Tokens.spacingXs

    Button {
      id: setup
      visible: root.compact && root.setupLabel !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.setupLabel
      variant: "primary"
      activeFocusOnTab: false
      onClicked: root.detailRequested()
    }

    Rectangle {
      id: detail
      visible: root.hasDetail && !setup.visible && !root.unavailable
      width: Tokens.controlHeight - 4
      height: width
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: detailArea.pressed ? Tokens.surfacePressed : root.compact && !detailArea.containsMouse ? "transparent" : Tokens.surfaceRaised
      opacity: root.showChevron ? 1 : 0
      Accessible.role: Accessible.Button
      Accessible.name: root.detailLabel
      Behavior on opacity { NumberAnimation { duration: Tokens.animationFast } }

      Glyph {
        anchors.centerIn: parent
        glyph: "󰅂"
        size: Tokens.iconSizeSmall
        color: Tokens.muted
      }

      MouseArea {
        id: detailArea
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.detailRequested()
      }
    }
  }

  MouseArea {
    id: bodyArea
    anchors.fill: parent
    anchors.rightMargin: root.compact && trailing.width > 0 ? trailing.width + Tokens.spacing : 0
    z: -1
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: root.unavailable ? Qt.ArrowCursor : Qt.PointingHandCursor
    onClicked: mouse => {
      root.forceActiveFocus()
      if (mouse.button === Qt.RightButton && root.hasDetail && !root.unavailable) root.detailRequested()
      else root.activate()
    }
  }
}
