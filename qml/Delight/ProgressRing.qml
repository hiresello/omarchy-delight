import QtQuick

// Circular progress. `value` is 0..1; `indeterminate` spins a fixed arc.
// Optional centre text via `label`.
Item {
  id: root

  property real value: 0
  property bool indeterminate: false
  property real thickness: Math.max(2, Math.round(width / 12))
  property color color: Tokens.accent
  property color trackColor: Tokens.alpha(Tokens.foreground, 0.12)
  property string label: ""

  implicitWidth: 40
  implicitHeight: 40

  readonly property real clamped: Math.max(0, Math.min(1, value))
  property real shownValue: indeterminate ? 0.28 : clamped

  Behavior on shownValue {
    enabled: !root.indeterminate
    NumberAnimation { duration: Tokens.animationNormal; easing.type: Tokens.easing }
  }

  onShownValueChanged: canvas.requestPaint()
  onColorChanged: canvas.requestPaint()
  onTrackColorChanged: canvas.requestPaint()
  onThicknessChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      let ctx = getContext("2d")
      ctx.reset()
      let r = Math.min(width, height) / 2 - root.thickness / 2
      if (r <= 0) return
      let cx = width / 2
      let cy = height / 2
      ctx.lineWidth = root.thickness
      ctx.lineCap = "round"
      ctx.strokeStyle = root.trackColor
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.stroke()
      if (root.shownValue <= 0) return
      ctx.strokeStyle = root.color
      ctx.beginPath()
      ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * root.shownValue)
      ctx.stroke()
    }

    RotationAnimator on rotation {
      running: root.indeterminate && root.visible
      from: 0
      to: 360
      duration: 900
      loops: Animation.Infinite
    }
  }

  Text {
    anchors.centerIn: parent
    visible: root.label !== ""
    text: root.label
    color: Tokens.foreground
    font.family: Tokens.fontFamily
    font.pixelSize: Math.max(Tokens.fontSizeCaption, Math.round(root.height / 4))
  }
}
