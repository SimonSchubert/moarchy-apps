// Theme.js: how a theme file is read, and the arithmetic the tokens use.
//
// The fallbacks are the ones the shell's Commons/Color.qml applies, so an app
// and the shell around it agree on every colour of the same file.
import QtQuick
import QtTest
import "../Theme.js" as Theme

TestCase {
  name: "KitTheme"

  function test_named_keys_are_read_as_given() {
    var c = Theme.parseColors('background = "#11121A"\nforeground = "#c8d3f5"\naccent = "#82aaff"\nred = "#ff757f"\n')
    compare(c.background, "#11121a")
    compare(c.foreground, "#c8d3f5")
    compare(c.accent, "#82aaff")
    compare(c.red, "#ff757f")
    // No muted and no color8: the foreground stands in.
    compare(c.muted, "#c8d3f5")
  }

  function test_a_terminal_palette_fills_the_named_keys() {
    var raw = ""
    var hexes = ["#000000", "#aa0000", "#00aa00", "#aaaa00", "#0000aa", "#aa00aa", "#00aaaa", "#aaaaaa", "#555555"]
    for (var i = 0; i < hexes.length; i++) raw += "color" + i + " = '" + hexes[i] + "'\n"
    var c = Theme.parseColors(raw)
    compare(c.background, "#000000")
    compare(c.foreground, "#aaaaaa")
    compare(c.accent, "#0000aa")
    compare(c.muted, "#555555")
    compare(c.green, "#00aa00")
    compare(c.cyan, "#00aaaa")
  }

  function test_nothing_readable_is_an_empty_theme() {
    var c = Theme.parseColors("# a comment\nbackground = blue\n")
    compare(c.background, undefined)
    compare(c.muted, undefined)
  }

  function test_only_the_menu_table_is_read_from_shell_toml() {
    var m = Theme.parseMenu('[bar]\nbackground = "#000000"\n[menu]\nbackground = "#101010" # dark\ntext = "#eeeeee"\n[other]\ntext = "#ffffff"\n')
    compare(m.background, "#101010")
    compare(m.text, "#eeeeee")
  }

  function test_hex_accepts_six_digits_only() {
    compare(Theme.hex("#a1b2c3"), "#a1b2c3")
    compare(Theme.hex("#abc"), "")
    compare(Theme.hex(undefined), "")
  }

  function test_light_and_dark() {
    verify(Theme.isDark("#1e1e2e"))
    verify(!Theme.isDark("#fafafa"))
    compare(Theme.onColor("#fafafa"), "#111111")
    compare(Theme.onColor("#2563eb"), "#ffffff")
    compare(Theme.fallback(true).background, "#1e1e2e")
    compare(Theme.fallback(false).background, "#fafafa")
  }

  function test_a_muted_that_is_a_border_colour_does_not_read() {
    verify(!Theme.mutedReads("#2a2a3a", "#1e1e2e"))
    verify(Theme.mutedReads("#9a9aae", "#1e1e2e"))
  }

  function test_close_hues_are_alike_and_greys_are_alike_only_to_greys() {
    verify(Theme.alike("#ff0000", "#ff5500"))
    verify(!Theme.alike("#ff0000", "#00ff00"))
    verify(Theme.alike("#808080", "#202020"))
    verify(!Theme.alike("#808080", "#ff0000"))
  }

  function test_radius_is_clamped_and_zero_means_not_yet_known() {
    compare(Theme.radius(0), 10)
    compare(Theme.radius(undefined), 10)
    compare(Theme.radius(3), 6)
    compare(Theme.radius(8), 8)
    compare(Theme.radius(30), 12)
  }
}
