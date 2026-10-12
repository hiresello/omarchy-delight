pragma Singleton

import QtQuick
import qs.Commons
import qs.Commons as Commons

// Design tokens for Delight UI. Every value binds to the live Omarchy theme
// (Commons.Color, Style), so `omarchy-theme-set` restyles open surfaces in
// place; values fall back to Omarchy's own defaults when a theme leaves one unset.
QtObject {
  id: root

  function pick(value, fallback) {
    return value && String(value) !== "#00000000" ? value : fallback
  }

  function alpha(c, a) {
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  function mix(a, b, amount) {
    return Qt.rgba(a.r + (b.r - a.r) * amount, a.g + (b.g - a.g) * amount,
      a.b + (b.b - a.b) * amount, a.a + (b.a - a.a) * amount)
  }

  // Relative luminance, for picking legible text on a filled color.
  function luminance(c) {
    return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
  }

  function onColor(fill) {
    return luminance(fill) > 0.55 ? Qt.rgba(0.07, 0.07, 0.08, 1) : Qt.rgba(1, 1, 1, 1)
  }

  // Typed as var: qmllint only sees these nested theme objects as QObject.
  readonly property var themeFont: Style.font
  readonly property var themePopups: Commons.Color.popups

  // ---- color: theme palette
  readonly property color foreground: pick(Commons.Color.foreground, "#cacccc")
  readonly property color background: pick(Commons.Color.background, "#101315")
  readonly property color accent: pick(Commons.Color.accent, "#cacccc")
  readonly property color urgent: pick(Commons.Color.urgent, "#a55555")
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
  readonly property bool dark: luminance(background) < 0.5

  // ---- color: surfaces (derived, so every theme gets the same hierarchy)
  readonly property color sheetBackground: alpha(pick(themePopups.background, background), 0.96)
  readonly property color sheetBorder: alpha(pick(themePopups.border, foreground), 0.35)
  readonly property color surface: Qt.tint(background, alpha(foreground, 0.06))
  readonly property color surfaceRaised: Qt.tint(background, alpha(foreground, 0.12))
  readonly property color surfacePressed: Qt.tint(background, alpha(foreground, 0.18))
  readonly property color border: alpha(foreground, 0.14)
  readonly property color divider: alpha(foreground, 0.08)
  readonly property color focusRing: accent
  readonly property color scrim: Qt.rgba(0, 0, 0, 0.55)
  readonly property color onAccent: onColor(accent)
  readonly property color onUrgent: onColor(urgent)
  readonly property color success: mix(accent, "#4cc38a", 0.6)
  readonly property color warning: mix(urgent, "#e5a50a", 0.6)

  // ---- typography (Style.font scales with `[font] base-size`)
  readonly property string fontFamily: pick(themeFont.family, "monospace")
  readonly property int fontSizeCaption: themeFont.caption
  readonly property int fontSizeSmall: themeFont.bodySmall
  readonly property int fontSize: themeFont.subtitle
  readonly property int fontSizeTitle: themeFont.title
  readonly property int fontSizeHeading: themeFont.heading
  readonly property int fontSizeDisplay: themeFont.display
  readonly property int iconSize: themeFont.iconLarge
  readonly property int iconSizeSmall: themeFont.icon
  readonly property int iconSizeLarge: Math.round(themeFont.iconLarge * 1.35)

  // ---- shape. Delight is rounded by default; a theme radius above ours wins.
  readonly property int radius: Math.max(Style.space(14), Style.cornerRadius)
  readonly property int radiusSmall: Math.max(Style.space(10), Style.cornerRadius)
  readonly property int radiusLarge: Math.max(Style.space(20), Style.cornerRadius)
  readonly property int borderWidth: 1
  readonly property int focusWidth: 2

  // ---- spacing (Style.space follows `[spacing] scale`)
  readonly property int spacingXs: Style.space(4)
  readonly property int spacingSmall: Style.space(6)
  readonly property int spacing: Style.space(8)
  readonly property int spacingLarge: Style.space(12)
  readonly property int padding: Style.space(12)
  readonly property int paddingLarge: Style.space(18)
  readonly property int sheetWidth: Style.space(440)
  readonly property int tileHeight: Style.space(66)
  readonly property int rowHeight: Style.space(48)
  readonly property int badgeSize: Style.space(34)
  readonly property int controlHeight: Style.space(30)

  // ---- motion (0 when Hyprland animations are off / reduce-motion)
  readonly property bool reduceMotion: Style.reduceMotion
  readonly property int animationFast: duration(120)
  readonly property int animationNormal: duration(200)
  readonly property int animationSlow: duration(320)
  readonly property int easing: Easing.OutCubic
  readonly property int easingEmphasized: Easing.OutBack
  readonly property int easingExit: Easing.InCubic

  function duration(ms) {
    return reduceMotion ? 0 : ms
  }

  // ---- state
  function stateColor(state) {
    switch (state) {
    case "on": return accent
    case "busy": return mix(surfaceRaised, accent, 0.45)
    case "error": return urgent
    case "unsupported":
    case "needs-setup": return surface
    default: return surfaceRaised
    }
  }

  function stateTextColor(state) {
    switch (state) {
    case "on": return onAccent
    case "error": return onUrgent
    case "unsupported": return muted
    default: return foreground
    }
  }

  function stateLabel(state) {
    switch (state) {
    case "on": return "On"
    case "off": return "Off"
    case "busy": return "Working…"
    case "needs-setup": return "Set up"
    case "unsupported": return "Unavailable"
    case "error": return "Error"
    default: return ""
    }
  }

  // Nerd Font glyphs for device and share-target kinds.
  function kindIcon(kind) {
    switch (kind) {
    case "phone": return "󰄜"
    case "tablet": return "󰓶"
    case "laptop": return "󰌢"
    case "computer":
    case "desktop": return "󰇄"
    case "tv":
    case "display": return "󰔂"
    case "speaker":
    case "audio": return "󰓃"
    case "headphones": return "󰋋"
    case "watch": return "󰖉"
    case "keyboard": return "󰌌"
    case "mouse": return "󰍽"
    case "camera": return "󰄀"
    case "clipboard": return "󰅌"
    case "folder": return "󰉋"
    case "link": return "󰌹"
    default: return "󰾰"
    }
  }
}
