"""Where every card on the table is, as arithmetic.

Split out of `widgets.py` for one reason: **where a card is drawn and where a
tap lands are the same function**, so a bug in it is a game that plays the wrong
card -- and that is worth testing on any machine rather than only on one with a
display. `widgets.py` imports GTK and cairo at module scope, which is right for
a widget and means a build chroot cannot import it at all; this file imports
nothing but `dataclasses` and the rules, so the geometry is checked in the same
place the rules are.

It was moved here after `makepkg` refused the package: the check() in the
PKGBUILD runs the tests in a chroot with no GTK, the layout tests imported the
widget to reach two functions, and the whole test module failed to load. The
tests had already claimed in their own docstring that the layout was "tested as
arithmetic rather than through a widget", which was true of the assertions and
not of the imports.
"""

from __future__ import annotations

from dataclasses import dataclass

from .klondike import (
    COLUMNS,
    FOUNDATION,
    STOCK,
    TABLEAU,
    WASTE,
    Table,
    is_foundation,
    is_tableau,
)

# A card, as a ratio. Poker cards are 2.5 by 3.5; this is a little squarer,
# because the width is fixed by seven columns on a 360px screen and the height
# is what pays for the extra tableau rows.
ASPECT = 1.45

MARGIN = 5.0
GAP = 4.0
# Between the top row and the tableau. Enough that the two are separate things.
SPLIT = 12.0

# How much of a covered card shows. The face-up figure is the one that has to
# hold an index; the face-down one only has to say "there is another card here".
#
# Fixed rather than fitted to the tallest column. Spreading the cards out to
# fill the screen would be a better use of a 720px phone right up until a column
# grew or shrank, at which point every card on the table would move -- and a
# table that rearranges itself under a thumb is a table nobody can aim at. 0.42
# of a card is what makes a column of six face-down and thirteen face-up cards,
# which is the tallest a Klondike column gets, land exactly on the bottom of a
# 360x720 screen.
UP_SHARE = 0.42
DOWN_SHARE = 0.14
# ...and how far either may be squeezed when a column grows past the screen.
# Below this a column stops being readable as cards at all, and the app would
# rather run off the bottom, where a scroll is at least a thing people know.
SQUEEZE = 0.45

# How far the three cards of a draw-three deal are fanned across the waste. They
# spread into the empty slot between the waste and the first foundation, which
# is the only reason that slot is empty.
FAN = 0.34

# The smallest table worth drawing. Below this a card is under 34px and the rank
# in the corner stops being a letter.
MINIMUM = 290


@dataclass(frozen=True)
class Layout:
    """Where everything is, worked out once per frame from the widget size."""

    card_w: float
    card_h: float
    stride: float
    left: float
    top: float
    tableau_y: float
    up_step: float
    down_step: float

    def slot_x(self, index: int) -> float:
        return self.left + index * self.stride


def column_of(pile: int) -> int:
    """Which of the seven slots across the screen a pile sits in.

    The stock and the waste take the first two, the four foundations take the
    last four, and the slot between them is left empty on purpose: it is where a
    three-card deal fans out to.
    """
    if pile == STOCK:
        return 0
    if pile == WASTE:
        return 1
    if is_foundation(pile):
        return 3 + (pile - FOUNDATION)
    return pile - TABLEAU


def layout_for(width: float, height: float, table: Table) -> Layout:
    width = max(width, MINIMUM)
    card_w = (width - 2 * MARGIN - (COLUMNS - 1) * GAP) / COLUMNS
    card_h = card_w * ASPECT
    stride = card_w + GAP
    left = (width - (COLUMNS * card_w + (COLUMNS - 1) * GAP)) / 2
    tableau_y = MARGIN + card_h + SPLIT

    up_step = card_h * UP_SHARE
    down_step = card_h * DOWN_SHARE
    # The tallest column decides the squeeze for all seven, so that a card is
    # the same size everywhere on the table. Seven different overlaps would be
    # seven different-looking columns of the same fifty-two cards.
    tallest = 0.0
    for index in range(COLUMNS):
        hidden = table.down[index]
        shown = max(len(table.piles[index]) - hidden, 0)
        tallest = max(tallest, hidden * down_step + max(shown - 1, 0) * up_step)
    room = height - tableau_y - card_h - MARGIN
    if tallest > room > 0:
        shrink = max(room / tallest, SQUEEZE)
        up_step *= shrink
        down_step *= shrink
    return Layout(
        card_w=card_w,
        card_h=card_h,
        stride=stride,
        left=left,
        top=MARGIN,
        tableau_y=tableau_y,
        up_step=up_step,
        down_step=down_step,
    )


def card_at(layout: Layout, table: Table, pile: int, position: int) -> tuple:
    """The rectangle a given card in a given pile occupies."""
    x = layout.slot_x(column_of(pile))
    if is_tableau(pile):
        hidden = table.hidden(pile)
        if position < hidden:
            offset = position * layout.down_step
        else:
            offset = hidden * layout.down_step + (position - hidden) * layout.up_step
        return x, layout.tableau_y + offset, layout.card_w, layout.card_h
    if pile == WASTE:
        # Only the last few are drawn, fanned to the right. `position` is an
        # index into the whole waste, so it is turned into a place in the fan.
        shown = min(len(table.waste), table.draw)
        place = position - (len(table.waste) - shown)
        offset = max(place, 0) * layout.card_w * FAN
        return x + offset, layout.top, layout.card_w, layout.card_h
    return x, layout.top, layout.card_w, layout.card_h
