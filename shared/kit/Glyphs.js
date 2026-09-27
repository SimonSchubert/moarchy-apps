.pragma library

// Nerd Font (Material Design) glyphs the kit itself draws, by name, each one
// checked against its md- name in nerd-fonts' glyphnames.json. An app keeps
// its own Glyphs.js for everything else. A raw codepoint in a view says
// nothing about what it should look like.
function g(cp) { return String.fromCodePoint(cp) }

var back = g(0xF004D)           // md-arrow_left
var close = g(0xF0156)          // md-close
var settings = g(0xF08BB)       // md-cog_outline
var search = g(0xF0349)         // md-magnify
var check = g(0xF012C)          // md-check
var plus = g(0xF0415)           // md-plus
var minus = g(0xF0374)          // md-minus
var refresh = g(0xF0450)        // md-refresh
var remove = g(0xF09E7)         // md-delete_outline
var info = g(0xF02FD)           // md-information_outline
var alert = g(0xF05D6)          // md-alert_circle_outline
var chevronRight = g(0xF0142)   // md-chevron_right
var chevronDown = g(0xF0140)    // md-chevron_down
var star = g(0xF04CE)           // md-star
var starOutline = g(0xF04D2)    // md-star_outline
var play = g(0xF040A)           // md-play
var pause = g(0xF03E4)          // md-pause
var undo = g(0xF054C)           // md-undo
var history = g(0xF02DA)        // md-history
var sort = g(0xF04BA)           // md-sort
var open = g(0xF03CC)           // md-open_in_new
