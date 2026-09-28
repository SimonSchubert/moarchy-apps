// The arithmetic behind HostTheme and Tokens, and every colour they fall back
// to, kept out of QML so a view never writes one.

// colors.toml, key -> "#rrggbb". Read the way the shell's Commons/Color.qml
// reads it, fallbacks included, so the app and the shell agree on every colour
// of a theme that names only color0..color15.
export function parseColors(raw) {
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
  return out
}

// The [menu] table of the theme's shell.toml: the colours the shell draws its
// own windows in, which win over colors.toml's where a theme sets them.
export function parseMenu(raw) {
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

export function hex(v) { return typeof v === "string" && /^#[0-9A-Fa-f]{6}$/.test(v) ? v : "" }

// With no Omarchy theme: light or dark with the desktop.
const PLAIN = {
  dark: { background: "#1e1e2e", text: "#e6e6ef", muted: "#9a9aae", accent: "#89b4fa", border: "#3a3a4e" },
  light: { background: "#fafafa", text: "#1f1f28", muted: "#6b6b78", accent: "#1e66f5", border: "#d8d8e0" }
}
export function plain(dark) { return dark ? PLAIN.dark : PLAIN.light }

// On time, late and a few minutes late, and the star on what is kept. A
// theme's own green, red and yellow take over where they read on its
// background; these are for where they do not.
const STATE = {
  dark: { ok: "#34d399", late: "#f87171", warn: "#fbbf24", star: "#f5b82e" },
  light: { ok: "#15803d", late: "#dc2626", warn: "#b45309", star: "#d97706" }
}
export function state(dark) { return dark ? STATE.dark : STATE.light }

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
export function luminance(c) {
  var x = rgb(c)
  return 0.2126 * x.r + 0.7152 * x.g + 0.0722 * x.b
}

export function contrast(a, b) {
  var x = luminance(a) + 0.05, y = luminance(b) + 0.05
  return x > y ? x / y : y / x
}

// A theme's muted is sometimes a border colour, too faint for a caption. Then
// the caller uses the text faded instead, which reads as the same role.
export function mutedReads(muted, background) {
  return Math.abs(luminance(muted) - luminance(background)) >= 0.28
}

// Whether a colour reads as the hue it is named for. Late has to look red and
// on time green: a theme drawn in one colour names its red a grey, or a green,
// and then ours stands in.
const HUES = { red: [335, 25], green: [75, 170], yellow: [25, 65] }
export function looksLike(c, name) {
  var x = rgb(c)
  var max = Math.max(x.r, x.g, x.b), min = Math.min(x.r, x.g, x.b)
  var d = max - min
  if (d < 0.2) return false
  var h = max === x.r ? ((x.g - x.b) / d + 6) % 6 : max === x.g ? (x.b - x.r) / d + 2 : (x.r - x.g) / d + 4
  h *= 60
  var range = HUES[name]
  if (!range) return true
  return range[0] > range[1] ? h >= range[0] || h <= range[1] : h >= range[0] && h <= range[1]
}
