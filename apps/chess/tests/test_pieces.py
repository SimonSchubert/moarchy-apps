"""The artwork, and the path reader that turns it into something drawable.

Two claims. The first is that all six pieces parse -- which sounds like nothing
until you remember that a path this reader chokes on does not raise at draw
time, it draws an empty shape, and an empty shape on a chessboard is a missing
piece that only a person looking at a screenshot will ever notice.

The second is that each one lands inside the box it says it occupies, because
the board scales them by that box: a piece whose outline ran past it would be
drawn over its neighbours.

No cairo here. The reader produces plain tuples, so this runs on any machine
with a Python, and the drawing function is checked against a context that only
writes down what it was asked to do.
"""

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_chess import pieces  # noqa: E402
from moarchy_chess.chess import KINDS  # noqa: E402

# A Bézier is measured here by its control points, which can only overstate the
# box it fills -- the curve stays inside their hull. So a couple of units of
# overshoot on a 512-unit piece is the measurement being conservative, not the
# artwork being wrong.
SLACK = 4.0


class Recorder:
    """Enough of a cairo context to say what was drawn on it."""

    def __init__(self):
        self.calls = []
        self.stack = []
        self.offset = (0.0, 0.0)
        self.scale_by = (1.0, 1.0)

    def save(self):
        self.stack.append((self.offset, self.scale_by))

    def restore(self):
        self.offset, self.scale_by = self.stack.pop()

    def translate(self, x, y):
        self.offset = (self.offset[0] + x, self.offset[1] + y)

    def scale(self, x, y):
        self.scale_by = (self.scale_by[0] * x, self.scale_by[1] * y)

    def _at(self, x, y):
        return (
            self.offset[0] + x * self.scale_by[0],
            self.offset[1] + y * self.scale_by[1],
        )

    def new_sub_path(self):
        self.calls.append(("new_sub_path",))

    def move_to(self, x, y):
        self.calls.append(("move_to", *self._at(x, y)))

    def line_to(self, x, y):
        self.calls.append(("line_to", *self._at(x, y)))

    def curve_to(self, x1, y1, x2, y2, x, y):
        self.calls.append(
            ("curve_to", *self._at(x1, y1), *self._at(x2, y2), *self._at(x, y))
        )

    def close_path(self):
        self.calls.append(("close_path",))

    def points(self):
        out = []
        for call in self.calls:
            for index in range(1, len(call), 2):
                out.append((call[index], call[index + 1]))
        return out


class Outlines(unittest.TestCase):
    def test_every_piece_has_one(self):
        self.assertEqual(set(pieces.OUTLINES), set(KINDS))

    def test_every_outline_has_something_in_it(self):
        for kind in KINDS:
            self.assertGreater(len(pieces.OUTLINES[kind][1]), 8, pieces.NAMES[kind])

    def test_every_outline_starts_by_moving_and_ends_closed(self):
        for kind in KINDS:
            ops = pieces.OUTLINES[kind][1]
            self.assertEqual(ops[0][0], "M", pieces.NAMES[kind])
            self.assertEqual(ops[-1][0], "Z", pieces.NAMES[kind])

    def test_every_outline_fits_the_box_it_claims(self):
        for kind in KINDS:
            width, _ = pieces.OUTLINES[kind]
            left, top, right, bottom = pieces.extent(kind)
            self.assertGreaterEqual(left, -SLACK, pieces.NAMES[kind])
            self.assertLessEqual(right, width + SLACK, pieces.NAMES[kind])
            self.assertGreaterEqual(top, -SLACK, pieces.NAMES[kind])
            self.assertLessEqual(bottom, pieces.HEIGHT + SLACK, pieces.NAMES[kind])

    def test_every_outline_fills_the_height_it_is_scaled_by(self):
        """A piece that used half its box would be drawn half size."""
        for kind in KINDS:
            _, top, _, bottom = pieces.extent(kind)
            self.assertGreater(bottom - top, pieces.HEIGHT * 0.85, pieces.NAMES[kind])


class Reader(unittest.TestCase):
    def test_absolute_and_relative_lines_agree(self):
        self.assertEqual(
            pieces.parse("M10,10 L20,20 L20,10 Z"),
            pieces.parse("m10,10 l10,10 l0,-10 z"),
        )

    def test_horizontal_and_vertical_become_lines(self):
        self.assertEqual(
            pieces.parse("M0,0 H10 V10 Z"),
            [("M", 0.0, 0.0), ("L", 10.0, 0.0), ("L", 10.0, 10.0), ("Z",)],
        )

    def test_a_second_pair_after_a_moveto_is_a_lineto(self):
        self.assertEqual(
            pieces.parse("M0,0 5,5 10,0"),
            [("M", 0.0, 0.0), ("L", 5.0, 5.0), ("L", 10.0, 0.0)],
        )

    def test_a_repeated_command_letter_may_be_left_out(self):
        self.assertEqual(
            pieces.parse("M0,0 L1,1 2,2"),
            [("M", 0.0, 0.0), ("L", 1.0, 1.0), ("L", 2.0, 2.0)],
        )

    def test_a_quadratic_becomes_the_cubic_it_is(self):
        (_, curve) = pieces.parse("M0,0 Q6,0 6,6")
        self.assertEqual(curve[0], "C")
        self.assertAlmostEqual(curve[1], 4.0)
        self.assertAlmostEqual(curve[2], 0.0)
        self.assertAlmostEqual(curve[5], 6.0)
        self.assertAlmostEqual(curve[6], 6.0)

    def test_a_smooth_curve_reflects_the_last_control_point(self):
        ops = pieces.parse("M0,0 C1,1 2,2 3,3 S5,5 6,6")
        self.assertAlmostEqual(ops[2][1], 4.0)
        self.assertAlmostEqual(ops[2][2], 4.0)

    def test_an_arc_ends_where_it_was_told_to(self):
        ops = pieces.parse("M0,0 A10,10 0 0 1 20,0")
        self.assertAlmostEqual(ops[-1][5], 20.0, places=6)
        self.assertAlmostEqual(ops[-1][6], 0.0, places=6)

    def test_an_arc_bulges_the_way_the_sweep_flag_says(self):
        """Sweep 1 is the positive-angle direction, which on a y-down canvas
        goes over the top -- so the curve leaves through negative y."""
        over = pieces.parse("M0,0 A10,10 0 0 1 20,0")
        under = pieces.parse("M0,0 A10,10 0 0 0 20,0")
        self.assertLess(min(op[2] for op in over[1:]), 0)
        self.assertGreater(max(op[2] for op in under[1:]), 0)

    def test_an_arc_with_no_radius_is_a_line(self):
        self.assertEqual(
            pieces.parse("M0,0 A0,0 0 0 1 20,0"),
            [("M", 0.0, 0.0), ("L", 20.0, 0.0)],
        )

    def test_flags_packed_against_their_coordinates_are_still_flags(self):
        """`a16,16 0 0116,16` is two flags and a pair, not one number 0116."""
        packed = pieces.parse("M0,0 a10,10 0 0120,0")
        spaced = pieces.parse("M0,0 a10,10 0 0 1 20,0")
        self.assertEqual(packed, spaced)

    def test_data_that_is_not_a_path_is_refused(self):
        for text in ("L10,10", "M0,0 X5,5", "M0,0 L"):
            with self.assertRaises(ValueError, msg=text):
                pieces.parse(text)


class Drawing(unittest.TestCase):
    def test_a_piece_is_laid_out_inside_the_square_it_was_given(self):
        for kind in KINDS:
            cr = Recorder()
            pieces.path(cr, kind, 100.0, 200.0, 40.0)
            xs = [x for x, _ in cr.points()]
            ys = [y for _, y in cr.points()]
            self.assertGreaterEqual(min(xs), 100.0 - 1, pieces.NAMES[kind])
            self.assertLessEqual(max(xs), 140.0 + 1, pieces.NAMES[kind])
            self.assertGreaterEqual(min(ys), 200.0 - 1, pieces.NAMES[kind])
            self.assertLessEqual(max(ys), 240.0 + 1, pieces.NAMES[kind])

    def test_a_piece_is_centred_on_the_width_it_does_not_fill(self):
        cr = Recorder()
        pieces.path(cr, KINDS[0], 0.0, 0.0, 64.0)
        xs = [x for x, _ in cr.points()]
        # The pawn is 320 wide in a 512 box, so it should sit in the middle 5/8.
        self.assertAlmostEqual((min(xs) + max(xs)) / 2, 32.0, delta=1.0)

    def test_every_instruction_reaches_the_context(self):
        cr = Recorder()
        pieces.path(cr, KINDS[0], 0.0, 0.0, 64.0)
        kinds = {call[0] for call in cr.calls}
        self.assertEqual(
            kinds, {"move_to", "line_to", "curve_to", "close_path", "new_sub_path"}
        )

    def test_the_context_is_left_as_it_was_found(self):
        cr = Recorder()
        pieces.path(cr, KINDS[0], 10.0, 10.0, 64.0)
        self.assertEqual(cr.stack, [])
        self.assertEqual(cr.offset, (0.0, 0.0))
        self.assertEqual(cr.scale_by, (1.0, 1.0))


if __name__ == "__main__":
    unittest.main()
