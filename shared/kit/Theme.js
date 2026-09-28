.pragma library

// The arithmetic behind HostTheme and Tokens, kept out of QML so qmltestrunner
// can read it without a display, a shell or a theme on disk.

// colors.toml, key -> "#rrggbb". Read the way the shell's Commons/Color.qml
// reads it, fallbacks included, so the app and the shell agree on every colour
// of a theme that names only color0..color15.
function parseColors(raw) {
  var out = ({})
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (m) out[m[1]] = m[2].toLowerCase()
  }
  if (!out.background && out.color0) out.background = out.color0
  if (!out.foreground && out.color7) out.foreground = out.color7
  if (!out.accent && out.color4) out.accent = out.color4
  if (!out.muted) out.muted = out.color8 || out.foreground
  if (!out.red && out.color1) out.red = out.color1
  if (!out.green && out.color2) out.green = out.color2
  if (!out.yellow && out.color3) out.yellow = out.color3
  if (!out.blue && out.color4) out.blue = out.color4
  if (!out.magenta && out.color5) out.magenta = out.color5
  if (!out.cyan && out.color6) out.cyan = out.color6
  return out
}

// The [menu] table of the theme's shell.toml: the colours the shell draws its
// own windows in, which win over colors.toml's where a theme sets them.
function parseMenu(raw) {
  var out = ({})
  var section = ""
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    var s = line.match(/^\[([A-Za-z0-9_.-]+)\]/)
    if (s) { section = s[1]; continue }
    if (section !== "menu") continue
    // A quoted value keeps its '#': these are colours.
    var kv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s#]+))/)
    if (kv) out[kv[1]] = kv[2] !== undefined ? kv[2] : kv[3] !== undefined ? kv[3] : kv[4]
  }
  return out
}

function hex(v) { return typeof v === "string" && /^#[0-9A-Fa-f]{6}$/.test(v) ? v : "" }

// The plain palettes, for a machine with no Omarchy theme: Omarchy's own
// default, Tokyo Night, and its light sibling. Blue rather than a warm
// accent: an accent is a selection or a value on a graph, and a red or orange
// one reads as a warning at a glance.
var FALLBACK = {
  dark: { background: "#1a1b26", text: "#c0caf5", muted: "#787c99", accent: "#7aa2f7", border: "#2f3349" },
  light: { background: "#e1e2e7", text: "#3760bf", muted: "#6172b0", accent: "#2e7de9", border: "#c4c8da" }
}

function fallback(dark) { return dark ? FALLBACK.dark : FALLBACK.light }

// Colours as {r, g, b} in 0..1, whether a QML color or "#rrggbb".
function rgb(c) {
  if (typeof c === "string") {
    var h = hex(c)
    if (!h) return { r: 0, g: 0, b: 0 }
    return {
      r: parseInt(h.substr(1, 2), 16) / 255,
      g: parseInt(h.substr(3, 2), 16) / 255,
      b: parseInt(h.substr(5, 2), 16) / 255
    }
  }
  return { r: c.r, g: c.g, b: c.b }
}

// Relative luminance, near enough for "is this light or dark".
function luminance(c) {
  var x = rgb(c)
  return 0.2126 * x.r + 0.7152 * x.g + 0.0722 * x.b
}

function isDark(c) { return luminance(c) < 0.5 }

// Text on a filled accent: near-black on a light accent, white on a dark one.
function onColor(c) { return luminance(c) > 0.6 ? "#111111" : "#ffffff" }

// A theme's muted is sometimes a border colour, too faint for a caption. Then
// the caller uses the text faded instead, which reads as the same role.
function mutedReads(muted, background) {
  return Math.abs(luminance(muted) - luminance(background)) >= 0.28
}

function hueOf(c) {
  var x = rgb(c)
  var max = Math.max(x.r, x.g, x.b), min = Math.min(x.r, x.g, x.b)
  var l = (max + min) / 2
  var d = max - min
  if (d === 0) return { h: 0, s: 0, l: l }
  var s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
  var h
  if (max === x.r) h = ((x.g - x.b) / d + (x.g < x.b ? 6 : 0))
  else if (max === x.g) h = (x.b - x.r) / d + 2
  else h = (x.r - x.g) / d + 4
  return { h: h * 60, s: s, l: l }
}

// Whether two colours read as one at a glance: hues within 45 degrees, or two
// greys. A rose and an orange are both "warm" on a graph, however far apart
// their channels are.
function alike(a, b) {
  var x = hueOf(a), y = hueOf(b)
  if (x.s < 0.15 || y.s < 0.15) return x.s < 0.15 && y.s < 0.15
  var d = Math.abs(x.h - y.h)
  return Math.min(d, 360 - d) < 45
}

// The corner radius a box is drawn with: the shell's, which is Hyprland's
// window rounding, and Omarchy's is none. Square is the look, so anything
// unknown is square too, and a rounded theme is clamped to what a 360 px
// screen can carry.
function radius(shellRadius) {
  var r = Number(shellRadius)
  if (!isFinite(r) || r <= 0) return 0
  return Math.max(2, Math.min(12, Math.round(r)))
}
