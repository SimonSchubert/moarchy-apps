.pragma library

// Nerd Font (Material Design) glyphs, each checked against its md- name in
// nerd-fonts' glyphnames.json.
//
// Listing.js and Places.js still answer with freedesktop icon names --
// "folder-download-symbolic", "image-x-generic-symbolic" -- because those are
// what their tests pin, and a name says what a row is better than a codepoint
// does. `of(names)` turns the first one it knows into a glyph, which is how a
// list of names best-first was always meant to be read.
function g(cp) { return String.fromCodePoint(cp) }

var folder = g(0xF024B)          // md-folder
var file = g(0xF0224)            // md-file_outline
var up = g(0xF005D)              // md-arrow_up
var newFolder = g(0xF0B9D)       // md-folder_plus_outline
var copy = g(0xF018F)            // md-content_copy
var cut = g(0xF0190)             // md-content_cut
var paste = g(0xF0192)           // md-content_paste
var rename = g(0xF0CB6)          // md-pencil_outline
var trash = g(0xF0A7A)           // md-trash_can_outline
var purge = g(0xF0B89)           // md-delete_forever_outline
var more = g(0xF01D9)            // md-dots_vertical
var hidden = g(0xF06D0)          // md-eye_outline
var hiddenOff = g(0xF06D1)       // md-eye_off_outline
var places = g(0xF10B6)          // md-folder_home_outline
var files = g(0xF0645)           // md-file_tree
var open = g(0xF03CC)            // md-open_in_new

var BY_NAME = {
  "folder-symbolic": folder,
  "inode-directory-symbolic": folder,
  "text-x-generic-symbolic": g(0xF09ED),          // md-text_box_outline
  "image-x-generic-symbolic": g(0xF0976),         // md-image_outline
  "audio-x-generic-symbolic": g(0xF0387),         // md-music_note
  "video-x-generic-symbolic": g(0xF0FCF),         // md-movie_open_outline
  "x-office-document-symbolic": g(0xF09EE),       // md-file_document_outline
  "x-office-spreadsheet-symbolic": g(0xF0C7F),    // md-file_table_outline
  "x-office-presentation-symbolic": g(0xF0229),   // md-file_presentation_box
  "package-x-generic-symbolic": g(0xF03D7),       // md-package_variant_closed
  "font-x-generic-symbolic": g(0xF06D6),          // md-format_font
  "action-unavailable-symbolic": g(0xF0338),      // md-link_off
  "user-home-symbolic": g(0xF06A1),               // md-home_outline
  "user-desktop-symbolic": g(0xF0379),            // md-monitor
  "folder-download-symbolic": g(0xF10E9),         // md-folder_download_outline
  "folder-documents-symbolic": g(0xF19F7),        // md-folder_file_outline
  "folder-pictures-symbolic": g(0xF024F),         // md-folder_image
  "folder-music-symbolic": g(0xF135A),            // md-folder_music_outline
  "folder-videos-symbolic": g(0xF19FB),           // md-folder_play_outline
  "user-trash-symbolic": trash,
  "drive-harddisk-symbolic": g(0xF02CA),          // md-harddisk
  "drive-removable-media-symbolic": g(0xF0479)    // md-sd
}

function of(names) {
  var list = names && names.constructor === Array ? names : [names]
  for (var i = 0; i < list.length; i++)
    if (BY_NAME[list[i]] !== undefined) return BY_NAME[list[i]]
  return file
}
