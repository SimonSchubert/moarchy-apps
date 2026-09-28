.pragma library

// The arithmetic behind HostTheme and Panel's tokens, kept out of QML so
// qmltestrunner can read it without a display, a shell or a theme on disk.
// The reading of the theme files is the shared kit's (shared/kit/Theme.js),
// copied: this app ships without the kit.

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

// The plain palettes, for a machine with no Omarchy theme: the app's own
// look from before it read theme files.
var FALLBACK = {
  dark: { background: "#1e1e2e", text: "#e6e6ef", muted: "#9a9aae", accent: "#89b4fa", border: "#3a3a4e" },
  light: { background: "#fafafa", text: "#1f1f28", muted: "#6b6b78", accent: "#1e66f5", border: "#d8d8e0" }
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

// The hues a price's direction may be drawn in: a green for up, a red (a
// rose or a coral included) for down, and a gold for the star. Wide enough
// for every theme's own idea of the colour, narrow enough that a theme whose
// "red" is a blue, a green or a grey -- Lumon, Hackerman, White -- is not
// taken at its word.
var HUES = {
  green: { from: 65, to: 170 },
  red: { from: 320, to: 20 },
  yellow: { from: 30, to: 65 }
}

// Whether `c` reads as `name` on `background`: in the hue's range, coloured
// enough to be told from a grey, and far enough from the page to be read.
function reads(c, name, background) {
  if (!hex(c)) return false
  var x = hueOf(c), r = HUES[name]
  var inside = r.from <= r.to ? x.h >= r.from && x.h <= r.to : x.h >= r.from || x.h <= r.to
  return inside && x.s >= 0.15 && Math.abs(luminance(c) - luminance(background)) >= 0.2
}

// The theme's colour for `name` where it reads as one, else the fallback.
function tone(c, name, background, fallback) {
  return reads(c, name, background) ? c : fallback
}
