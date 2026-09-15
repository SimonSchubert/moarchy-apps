// The spacing scale, off the shell.
//
// Nothing here can test the *in-shell* answer -- that needs omarchy-shell on
// the import path -- so what is pinned is the half that has to be right
// everywhere else: with no shell to ask, an app gets the numbers it was
// written with, and a gap never scales away to nothing.
import QtQuick
import QtTest
import "../Metrics.js" as Metrics

TestCase {
  name: "Metrics"

  function test_off_the_shell_px_is_px() {
    compare(Metrics.space(10, null), 10)
    compare(Metrics.space(12, null), 12)
    compare(Metrics.space(40, null), 40)
  }

  function test_a_gap_never_scales_away_to_nothing() {
    // Style.space floors at 1 for the same reason: a separator that rounds to
    // zero is a layout that has quietly lost it.
    compare(Metrics.space(0.2, null), 1)
    compare(Metrics.space(0, null), 0)
    compare(Metrics.space(-4, null), 0)
  }

  function test_the_type_ladder_is_ratios_of_the_body() {
    compare(Metrics.typeSize(16, "body"), 16)
    compare(Metrics.typeSize(16, "title"), 22)
    compare(Metrics.typeSize(16, "subtitle"), 18)
    compare(Metrics.typeSize(16, "caption"), 14)
    compare(Metrics.typeSize(16, "overline"), 12)
    // An unknown role is the body rather than nothing.
    compare(Metrics.typeSize(16, "nonsense"), 16)
  }

  function test_body_falls_back_when_there_is_no_shell_to_ask() {
    compare(Metrics.shellBody(null), Metrics.BODY)
  }
}
