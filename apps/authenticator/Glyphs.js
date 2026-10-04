.pragma library

// The app's own Nerd Font (Material Design) glyphs, beyond the kit's, each
// checked against its md- name in nerd-fonts' glyphnames.json.
function g(cp) { return String.fromCodePoint(cp) }

var shieldKey = g(0xF0BC5)      // md-shield_key_outline
var edit = g(0xF0CB6)           // md-pencil_outline
var copy = g(0xF018F)           // md-content_copy
var paste = g(0xF0192)          // md-content_paste
var scan = g(0xF0433)           // md-qrcode_scan
var show = g(0xF06D0)           // md-eye_outline
var hide = g(0xF06D1)           // md-eye_off_outline
var link = g(0xF0339)           // md-link_variant
