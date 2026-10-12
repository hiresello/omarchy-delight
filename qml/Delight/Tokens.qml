pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
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

  // WCAG relative luminance, for picking legible text on a filled color.
  function linear(v) {
    return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
  }
  function luminance(c) {
    return 0.2126 * root.linear(c.r) + 0.7152 * root.linear(c.g) + 0.0722 * root.linear(c.b)
  }

  // White unless dark text has clearly more contrast (white wins near ties,
  // as on Apple's blue).
  function onColor(fill) {
    let l = root.luminance(fill)
    return (l + 0.05) / 0.05 > 1.3 * (1.05 / (l + 0.05)) ? Qt.rgba(0.07, 0.07, 0.08, 1) : Qt.rgba(1, 1, 1, 1)
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
  readonly property bool dark: luminance(background) < 0.2

  // ---- material. Liquid-glass-style sheets: a translucent tint, a sheen and a
  // bright rim, all static. Hyprland blurs behind them only while Omarchy's
  // Glassy look is on (the blur pass it already runs for the bar); otherwise
  // the same layers are drawn near-opaque, so no extra GPU work either way.
  property bool glassy: false
  readonly property string glassFlagDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/toggles/hypr"
  property bool windowGlass: false
  property bool barGlass: false
  // Omarchy's no-animations toggle also turns blur off.
  property bool noBlur: false
  function updateGlassy() { glassy = (windowGlass || barGlass) && !noBlur }
  readonly property FileView noBlurFlag: FileView {
    path: root.glassFlagDir + "/no-animations.lua"
    printErrors: false
    onLoaded: { root.noBlur = true; root.updateGlassy() }
    onLoadFailed: { root.noBlur = false; root.updateGlassy() }
  }
  readonly property FileView windowGlassFlag: FileView {
    path: root.glassFlagDir + "/window-glassy.lua"
    printErrors: false
    onLoaded: { root.windowGlass = true; root.updateGlassy() }
    onLoadFailed: { root.windowGlass = false; root.updateGlassy() }
  }
  readonly property FileView barGlassFlag: FileView {
    path: root.glassFlagDir + "/bar-glassy.lua"
    printErrors: false
    onLoaded: { root.barGlass = true; root.updateGlassy() }
    onLoadFailed: { root.barGlass = false; root.updateGlassy() }
  }
  // Re-read the Glassy flags and config; call when a surface opens. Two stats.
  function refresh() {
    windowGlassFlag.reload()
    barGlassFlag.reload()
    noBlurFlag.reload()
    configFile.reload()
  }

  readonly property color glassBase: pick(themePopups.background, background)
  readonly property color sheetBackground: alpha(glassBase, glassy ? (dark ? 0.58 : 0.66) : (dark ? 0.95 : 0.97))
  readonly property color sheetBorder: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)
  readonly property color glassRim: dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.9)
  readonly property color glassSheen: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.38)
  readonly property color shadowColor: Qt.rgba(0, 0, 0, dark ? 1 : 0.6)

  // Fills for controls on a sheet: translucent so the glass shows through.
  readonly property color surface: dark ? alpha(foreground, 0.06) : alpha(Qt.lighter(background, 1.1), 0.55)
  readonly property color surfaceRaised: dark ? alpha(foreground, 0.09) : alpha(Qt.lighter(background, 1.12), 0.82)
  readonly property color surfacePressed: dark ? alpha(foreground, 0.15) : alpha(foreground, 0.10)
  readonly property color border: dark ? alpha(foreground, 0.10) : alpha(foreground, 0.08)
  readonly property color divider: alpha(foreground, 0.07)
  readonly property color focusRing: accent
  readonly property color scrim: Qt.rgba(0, 0, 0, glassy ? 0.25 : 0.45)
  // Not `onAccent`: QML reserves `on<Upper>` names for signal handlers.
  readonly property color accentInk: onColor(accent)
  readonly property color urgentInk: onColor(urgent)
  readonly property color success: mix(accent, "#4cc38a", 0.6)
  readonly property color warning: mix(urgent, "#e5a50a", 0.6)

  // ---- typography. Delight surfaces use a proportional UI sans (Inter if
  // installed, else Noto Sans, which Omarchy ships); glyphs and code keep the
  // theme's Nerd Font. `"ui": {"font": "<family>|theme"}` in config.json wins.
  readonly property var installedFamilies: Qt.fontFamilies()
  function firstFamily(names, fallback) {
    for (let i = 0; i < names.length; i++) if (installedFamilies.indexOf(names[i]) !== -1) return names[i]
    return fallback
  }
  property string uiFontOverride: ""
  readonly property string themeFontFamily: pick(themeFont.family, "monospace")
  readonly property string fontFamily: uiFontOverride === "theme" ? themeFontFamily
    : uiFontOverride !== "" ? uiFontOverride
    : firstFamily(["Inter", "Inter Variable", "Noto Sans", "Cantarell", "DejaVu Sans"], "sans-serif")
  readonly property string iconFontFamily: themeFontFamily
  readonly property string monoFontFamily: themeFontFamily
  readonly property int fontBase: Math.max(1, themeFont.baseSize || 12)
  function fontPx(px) { return Math.max(1, Math.round(fontBase * px / 12)) }
  readonly property int fontSizeCaption: fontPx(11)
  readonly property int fontSizeSmall: fontPx(12)
  readonly property int fontSize: fontPx(13)
  readonly property int fontSizeTitle: fontPx(15)
  readonly property int fontSizeHeading: fontPx(17)
  readonly property int fontSizeDisplay: fontPx(24)
  readonly property int iconSize: fontPx(17)
  readonly property int iconSizeSmall: fontPx(14)
  readonly property int iconSizeLarge: fontPx(24)
  readonly property real letterSpacingTitle: -0.2

  readonly property FileView configFile: FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy-delight/config.json"
    blockLoading: true
    printErrors: false
    onLoaded: {
      let font = ""
      try { font = (JSON.parse(text()).ui || {}).font || "" } catch (e) { font = "" }
      root.uiFontOverride = String(font)
    }
    onLoadFailed: root.uiFontOverride = ""
  }

  // ---- shape. Corners are concentric: an inner radius is its container's
  // radius minus the padding between them. A theme radius above ours wins.
  readonly property int paddingLarge: Style.space(14)
  readonly property int padding: Style.space(12)
  readonly property int radius: Math.max(Style.space(14), Style.cornerRadius)
  readonly property int radiusLarge: Math.max(radius + paddingLarge, Style.cornerRadius)
  readonly property int radiusSmall: Math.max(Style.space(10), Style.cornerRadius)
  readonly property int borderWidth: 1
  readonly property int focusWidth: 2

  // ---- spacing, on a 4 px grid (Style.space follows `[spacing] scale`)
  readonly property int spacingXs: Style.space(4)
  readonly property int spacingSmall: Style.space(6)
  readonly property int spacing: Style.space(8)
  readonly property int spacingLarge: Style.space(12)
  readonly property int sheetWidth: Style.space(416)
  readonly property int tileHeight: Style.space(56)
  readonly property int rowHeight: Style.space(48)
  readonly property int badgeSize: Style.space(32)
  readonly property int controlHeight: Style.space(28)
  // Room around a floating card for its baked shadow (shadow.png).
  readonly property int shadowMargin: Style.space(28)

  // ---- motion (0 when Hyprland animations are off / reduce-motion)
  readonly property bool reduceMotion: Style.reduceMotion
  readonly property int animationFast: duration(120)
  readonly property int animationNormal: duration(180)
  readonly property int animationSlow: duration(280)
  readonly property int easing: Easing.OutCubic
  readonly property int easingSpring: Easing.OutQuart
  readonly property int easingEmphasized: Easing.OutBack
  readonly property int easingExit: Easing.InCubic

  function duration(ms) {
    return reduceMotion ? 0 : ms
  }

  // ---- state
  function stateColor(state) {
    switch (state) {
    case "on": return accent
    case "busy": return mix(surfacePressed, accent, 0.45)
    case "error": return urgent
    default: return surfacePressed
    }
  }

  function stateTextColor(state) {
    switch (state) {
    case "on": return accentInk
    case "error": return urgentInk
    case "unsupported": return muted
    default: return foreground
    }
  }

  function stateLabel(state) {
    switch (state) {
    case "on": return "On"
    case "off": return "Off"
    case "busy": return "Working…"
    case "needs-setup": return "Needs setup"
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
