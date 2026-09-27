.pragma library

// Nerd Font (Material Design) glyphs by name, each checked against the md-
// name in the font that draws it. A raw codepoint in a view says nothing about
// what it should look like.
function g(cp) { return String.fromCodePoint(cp) }

var radio = g(0xF0439)          // md-radio
var tower = g(0xF043B)          // md-radio_tower
var discover = g(0xF018C)       // md-compass_outline
var browse = g(0xF11D9)         // md-view_grid_outline
var favorites = g(0xF04D2)      // md-star_outline
var star = g(0xF04CE)           // md-star
var starOutline = g(0xF04D2)    // md-star_outline
var recent = g(0xF02DA)         // md-history
var search = g(0xF0349)         // md-magnify
var settings = g(0xF08BB)       // md-cog_outline
var back = g(0xF004D)           // md-arrow_left
var close = g(0xF0156)          // md-close
var check = g(0xF012C)          // md-check
var play = g(0xF040A)           // md-play
var pause = g(0xF03E4)          // md-pause
var stop = g(0xF04DB)           // md-stop
var volumeHigh = g(0xF057E)     // md-volume_high
var volumeMedium = g(0xF0580)   // md-volume_medium
var volumeLow = g(0xF057F)      // md-volume_low
var volumeOff = g(0xF0581)      // md-volume_off
var vote = g(0xF0514)           // md-thumb_up_outline
var voted = g(0xF0513)          // md-thumb_up
var sleep = g(0xF04B2)          // md-sleep
var earth = g(0xF01E7)          // md-earth
var language = g(0xF05CA)       // md-translate
var tag = g(0xF04F9)            // md-tag
var note = g(0xF0387)           // md-music_note
var open = g(0xF03CC)           // md-open_in_new
var web = g(0xF059F)            // md-web
var link = g(0xF0337)           // md-link
var alert = g(0xF05D6)          // md-alert_circle_outline
var refresh = g(0xF0450)        // md-refresh
var offline = g(0xF0164)        // md-cloud_off_outline
var live = g(0xF0003)           // md-access_point
var chevronRight = g(0xF0142)   // md-chevron_right
var chevronDown = g(0xF0140)    // md-chevron_down
var shuffle = g(0xF049D)        // md-shuffle
var trending = g(0xF0535)       // md-trending_up
var fire = g(0xF0238)           // md-fire
var heart = g(0xF02D1)          // md-heart
var marker = g(0xF034E)         // md-map_marker
var info = g(0xF02FD)           // md-information_outline
var remove = g(0xF09E7)         // md-delete_outline
var minus = g(0xF0374)          // md-minus
var plus = g(0xF0415)           // md-plus
var equalizer = g(0xF0EA2)      // md-equalizer
var sort = g(0xF04BA)           // md-sort

// One per genre tile on Discover.
var genre = {
  pop: g(0xF0387),              // md-music_note
  rock: g(0xF02C4),             // md-guitar_electric
  jazz: g(0xF0609),             // md-saxophone
  classical: g(0xF060F),        // md-violin
  electronic: g(0xF0EA2),       // md-equalizer
  dance: g(0xF140B),            // md-lightning_bolt
  hiphop: g(0xF036C),           // md-microphone
  news: g(0xF0395),             // md-newspaper
  talk: g(0xF05CB),             // md-account_voice
  chillout: g(0xF1055),         // md-palm_tree
  ambient: g(0xF0594),          // md-weather_night
  oldies: g(0xF099A),           // md-record_player
  "80s": g(0xF09D4),            // md-cassette
  country: g(0xF0771),          // md-guitar_acoustic
  folk: g(0xF032A),             // md-leaf
  metal: g(0xF02C5),            // md-guitar_pick
  soul: g(0xF02D1),             // md-heart
  blues: g(0xF1096),            // md-trumpet
  reggae: g(0xF059A),           // md-weather_sunset
  lounge: g(0xF0356),           // md-glass_cocktail
  sports: g(0xF04B8),           // md-soccer
  kids: g(0xF006C)              // md-baby
}
