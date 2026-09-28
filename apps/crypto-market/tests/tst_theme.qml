// Theme.js: how a theme file is read, and which of its colours a price's
// direction may be drawn in.
import QtQuick
import QtTest
import "../Theme.js" as Theme

TestCase {
  name: "CryptoMarketTheme"

  function test_a_terminal_palette_fills_the_named_keys() {
    var raw = ""
    var hexes = ["#000000", "#aa0000", "#00aa00", "#aaaa00", "#0000aa", "#aa00aa", "#00aaaa", "#aaaaaa", "#555555"]
    for (var i = 0; i < hexes.length; i++) raw += "color" + i + " = '" + hexes[i] + "'\n"
    var c = Theme.parseColors(raw)
    compare(c.background, "#000000")
    compare(c.foreground, "#aaaaaa")
    compare(c.accent, "#0000aa")
    compare(c.muted, "#555555")
    compare(c.red, "#aa0000")
    compare(c.green, "#00aa00")
  }

  function test_only_the_menu_table_is_read_from_shell_toml() {
    var m = Theme.parseMenu('[bar]\nbackground = "#000000"\n[menu]\nbackground = "#101010" # dark\ntext = "#eeeeee"\n')
    compare(m.background, "#101010")
    compare(m.text, "#eeeeee")
  }

  // Tokyo Night, Catppuccin Latte, Kanagawa: their own green and red.
  function test_a_green_and_a_red_are_taken_as_they_are() {
    compare(Theme.tone("#9ece6a", "green", "#1a1b26", "#fallbk"), "#9ece6a")
    compare(Theme.tone("#f7768e", "red", "#1a1b26", "#fallbk"), "#f7768e")
    compare(Theme.tone("#40a02b", "green", "#eff1f5", "#fallbk"), "#40a02b")
    compare(Theme.tone("#d20f39", "red", "#eff1f5", "#fallbk"), "#d20f39")
    compare(Theme.tone("#c34043", "red", "#1f1f28", "#fallbk"), "#c34043")
  }

  // Lumon's red is a blue, Hackerman's a green, White's a grey, Matte
  // Black's green a yellow, Rose Pine's green a teal.
  function test_a_theme_whose_red_or_green_is_not_one_gets_the_plain_pair() {
    compare(Theme.tone("#4d86b0", "red", "#16242d", "#f87171"), "#f87171")
    compare(Theme.tone("#50f872", "red", "#0b0c16", "#f87171"), "#f87171")
    compare(Theme.tone("#2a2a2a", "red", "#ffffff", "#dc2626"), "#dc2626")
    compare(Theme.tone("#ffc107", "green", "#121212", "#34d399"), "#34d399")
    compare(Theme.tone("#286983", "green", "#faf4ed", "#15803d"), "#15803d")
  }

  function test_a_colour_too_close_to_the_page_is_not_used() {
    verify(!Theme.reads("#2a4a2a", "green", "#1e1e1e"))
    verify(Theme.reads("#a6e3a1", "green", "#1e1e2e"))
  }

  function test_nothing_is_not_a_colour() {
    compare(Theme.tone("", "green", "#000000", "#34d399"), "#34d399")
    compare(Theme.tone(undefined, "red", "#000000", "#f87171"), "#f87171")
  }

  function test_a_muted_that_is_a_border_colour_does_not_read() {
    verify(!Theme.mutedReads("#acb0be", "#eff1f5"))
    verify(Theme.mutedReads("#9a9aae", "#1e1e2e"))
  }
}
