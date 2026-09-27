.pragma library

// Nerd Font (Material Design) glyphs Mail draws, by name, each looked up by
// its md- name in the patched font's own glyph table. The kit's are in
// kit/Glyphs.js.
function g(cp) { return String.fromCodePoint(cp) }

var inbox = g(0xF1274)          // md-inbox_outline
var sent = g(0xF1165)           // md-send_outline
var send = g(0xF048A)           // md-send
var sending = g(0xF1164)        // md-send_clock_outline
var draft = g(0xF0DC9)          // md-file_document_edit_outline
var trash = g(0xF0A7A)          // md-trash_can_outline
var junk = g(0xF0CE6)           // md-alert_octagon_outline
var archive = g(0xF120E)        // md-archive_outline
var folder = g(0xF0256)         // md-folder_outline
var folders = g(0xF0255)        // md-folder_multiple_outline
var star = g(0xF04CE)           // md-star
var starOutline = g(0xF04D2)    // md-star_outline
var attachment = g(0xF03E2)     // md-paperclip
var download = g(0xF01DA)       // md-download
var reply = g(0xF045A)          // md-reply
var replyAll = g(0xF045B)       // md-reply_all
var forward = g(0xF028D)        // md-forward
var compose = g(0xF03EB)        // md-pencil
var read = g(0xF05EF)           // md-email_open_outline
var unread = g(0xF0B92)         // md-email_mark_as_unread
var mail = g(0xF01F0)           // md-email_outline
var offline = g(0xF0164)        // md-cloud_off_outline
var more = g(0xF01D9)           // md-dots_vertical
var link = g(0xF0339)           // md-link_variant
var copy = g(0xF018F)           // md-content_copy
var open = g(0xF03CC)           // md-open_in_new
var account = g(0xF0B55)        // md-account_circle_outline
var logout = g(0xF0343)         // md-logout
var alert = g(0xF05D6)          // md-alert_circle_outline

// A folder's glyph, by the role the server gave it.
function forRole(role) {
  if (role === "inbox") return inbox
  if (role === "sent") return sent
  if (role === "drafts") return draft
  if (role === "trash") return trash
  if (role === "junk") return junk
  if (role === "flagged") return star
  if (role === "archive" || role === "all") return archive
  return folder
}
