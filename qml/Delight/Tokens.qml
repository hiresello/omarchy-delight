pragma Singleton

import QtQuick
import qs.Commons as Commons

// Design tokens for Delight UI. Colors follow the active Omarchy theme and
// fall back to Omarchy's own defaults when a theme leaves one unset.
QtObject {
  function pick(value, fallback) {
    return value && String(value) !== "#00000000" ? value : fallback
  }

  readonly property color foreground: pick(Commons.Color.foreground, "#cacccc")
  readonly property color background: pick(Commons.Color.background, "#101315")
  readonly property color accent: pick(Commons.Color.accent, "#cacccc")
  readonly property color urgent: pick(Commons.Color.urgent, "#a55555")
  readonly property color muted: pick(Commons.Color.muted, "#707880")

  readonly property color surface: Qt.tint(background, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.06))
  readonly property color surfaceRaised: Qt.tint(background, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12))
  readonly property color border: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)

  readonly property string fontFamily: "monospace"
  readonly property int fontSize: 13
  readonly property int fontSizeSmall: 11
  readonly property int iconSize: 18

  readonly property int radius: 14
  readonly property int radiusSmall: 10
  readonly property int spacing: 8
  readonly property int padding: 12

  readonly property int animationFast: 120
  readonly property int animationNormal: 200

  function stateColor(state) {
    switch (state) {
    case "on": return accent
    case "error": return urgent
    case "unsupported":
    case "needs-setup": return muted
    default: return surfaceRaised
    }
  }
}
