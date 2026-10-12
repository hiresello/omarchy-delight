import QtQuick

// Control Center tile for one module status. Large (default) for toggleable
// modules; `compact: true` renders a slim row. Clicking the body emits
// toggled() when toggleable, otherwise detailRequested(); the "…" button
// always emits detailRequested(). Keyboard: Space/Enter = body, "." or
// Shift+Enter = "…".
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
  // Reason wins over subtitle for states that must explain themselves.
  readonly property string caption: (unavailable || failed || status === "needs-setup") && reason !== ""
    ? reason : (subtitle !== "" ? subtitle : Tokens.stateLabel(status))

  implicitWidth: compact ? Tokens.sheetWidth : Math.round(Tokens.sheetWidth / 2)
  implicitHeight: compact ? Tokens.rowHeight : Tokens.tileHeight
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
    color: root.compact
      ? (root.hovered ? Tokens.surfaceRaised : "transparent")
      : (bodyArea.pressed ? Tokens.surfacePressed : root.hovered ? Qt.lighter(Tokens.surfaceRaised, 1.08) : Tokens.surfaceRaised)
    border.width: root.compact ? 0 : Tokens.borderWidth
    border.color: root.failed ? Tokens.alpha(Tokens.urgent, 0.6) : Tokens.border
    opacity: root.unavailable ? 0.62 : 1
    scale: bodyArea.pressed ? 0.98 : 1

    Behavior on color { ColorAnimation { duration: Tokens.animationFast } }
    Behavior on scale { NumberAnimation { duration: Tokens.animationFast; easing.type: Tokens.easing } }

    FocusRing { radius_: card.radius; shown: root.activeFocus }
  }

  // Round state badge; filled with the accent when on.
  Rectangle {
    id: badge
    anchors.left: parent.left
    anchors.leftMargin: root.compact ? Tokens.spacing : Tokens.padding
    anchors.verticalCenter: parent.verticalCenter
    width: root.compact ? Math.round(Tokens.badgeSize * 0.85) : Tokens.badgeSize
    height: width
    radius: width / 2
    color: root.active ? Tokens.accent : root.failed ? Tokens.urgent : Tokens.surfacePressed
    Behavior on color { ColorAnimation { duration: Tokens.animationNormal } }

    Glyph {
      anchors.centerIn: parent
      glyph: root.icon !== "" ? root.icon : "󰘔"
      size: root.compact ? Tokens.iconSizeSmall : Tokens.iconSize
      color: root.active ? Tokens.onAccent : root.failed ? Tokens.onUrgent : Tokens.foreground
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
    anchors.left: badge.right
    anchors.leftMargin: Tokens.spacingLarge - 2
    anchors.right: trailing.left
    anchors.rightMargin: Tokens.spacingSmall
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1

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
      maximumLineCount: 1
      color: root.failed ? Tokens.urgent : Tokens.muted
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSizeSmall
    }
  }

  Row {
    id: trailing
    anchors.right: parent.right
    anchors.rightMargin: root.compact ? Tokens.spacingSmall : Tokens.spacing
    anchors.verticalCenter: parent.verticalCenter
    spacing: Tokens.spacingXs

    Text {
      visible: root.compact && root.status !== "off"
      anchors.verticalCenter: parent.verticalCenter
      text: Tokens.stateLabel(root.status)
      color: root.failed ? Tokens.urgent : root.active ? Tokens.accent : Tokens.muted
      font.family: Tokens.fontFamily
      font.pixelSize: Tokens.fontSizeCaption
    }

    Rectangle {
      id: detail
      visible: root.hasDetail
      width: Tokens.controlHeight - 4
      height: width
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: detailArea.pressed ? Tokens.surfacePressed : detailArea.containsMouse ? Tokens.alpha(Tokens.foreground, 0.12) : "transparent"
      Accessible.role: Accessible.Button
      Accessible.name: root.detailLabel

      Glyph {
        anchors.centerIn: parent
        glyph: "󰇘"
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
    anchors.rightMargin: detail.visible ? trailing.width + Tokens.spacing : 0
    z: -1
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      root.forceActiveFocus()
      root.activate()
    }
  }
}
