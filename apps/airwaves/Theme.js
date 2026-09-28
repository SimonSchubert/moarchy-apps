.pragma library

// The arithmetic behind HostTheme, kept out of QML: reading Omarchy's theme
// files, and the plain palettes for a machine without one.

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

// Airwaves' own look where there is no Omarchy theme: a warm rose on ink, or
// on paper.
var FALLBACK = {
  dark: { background: "#1e1e2e", text: "#e6e6ef", muted: "#9a9aae", accent: "#fb7185", border: "#3a3a4e" },
  light: { background: "#fafafa", text: "#1f1f28", muted: "#6b6b78", accent: "#e11d48", border: "#d8d8e0" }
}

function fallback(dark) { return dark ? FALLBACK.dark : FALLBACK.light }

// Relative luminance of "#rrggbb", near enough for "is this light or dark".
function luminance(c) {
  var h = hex(c)
  if (!h) return 0
  return 0.2126 * parseInt(h.substr(1, 2), 16) / 255 + 0.7152 * parseInt(h.substr(3, 2), 16) / 255
    + 0.0722 * parseInt(h.substr(5, 2), 16) / 255
}

// A theme's muted is sometimes a border colour, too faint for a caption.
// A step stricter than the kit's 0.28: Airwaves sets its captions small, and
// retro-82's teal and osaka-jade's grey-green pass that and still blur into
// the page at 13 px.
function mutedReads(muted, background) {
  return Math.abs(luminance(muted) - luminance(background)) >= 0.33
}

// An accent is a play button, a selected tab, a playing station's name. One
// that sits in the page's own brightness -- a white theme's grey, a pale
// accent on a pale page -- is text on nothing; then the theme's text is the
// accent instead, which is what a monochrome theme means by one.
function accentReads(accent, background) {
  return Math.abs(luminance(accent) - luminance(background)) >= 0.2
}
