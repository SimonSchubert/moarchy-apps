"""The six pieces, as outlines a cairo context can be handed.

The shapes are Font Awesome Free's chess icons -- `fa-chess-king` and its five
neighbours, CC BY 4.0 -- which is where Braincup's `ic_chess_*.xml` drawables
come from, so the phone and the Android app draw the same pieces. What arrives
here is the single SVG path out of each of those files, and what leaves is a
list of move/line/curve instructions in the piece's own coordinates.

Why not simply load the SVGs? Because "load an SVG" on this stack means librsvg,
through a gdk-pixbuf loader that may or may not be installed, to produce a
texture that then has to be recoloured per side and rescaled per screen. That is
a runtime dependency, a failure mode that draws a broken-image glyph rather than
raising, and a cache of twelve bitmaps -- in exchange for not writing the
hundred and fifty lines below. The board is already a cairo drawing area for
Reversi's reasons; a path it can fill is the thing it actually wants.

So this is a small SVG path reader: absolute and relative forms of every
command these six paths use, with elliptical arcs turned into cubic Béziers on
the way past, because cairo draws circles but not rotated ellipses. It runs at
import, once, and the result is plain tuples -- no cairo, no GTK, which is what
lets `tests/test_pieces.py` check that all six parse and land inside the box
they claim, on a machine with neither installed.
"""

from __future__ import annotations

import math

from .chess import BISHOP, KING, KNIGHT, PAWN, QUEEN, ROOK

# Every Font Awesome chess icon is 512 tall and fills that height; only the
# width differs. So a piece is scaled by its height and centred on its width,
# which is what makes a knight wider than a pawn and exactly as tall -- the way
# they are drawn, rather than the way a real set is carved.
HEIGHT = 512.0

# The path data, verbatim from Braincup's drawables, minus the group translate
# that centred each one in a 512-wide viewport. The number beside it is the
# piece's own width.
SOURCES: dict[int, tuple[int, str]] = {
    PAWN: (
        320,
        (
            "M105.1,224 L80,224 a16,16 0,0 0,-16 16 v32 a16,16 0,0 0,16 16 h16 v5.49 "
            "c0,44 -4.14,86.6 -24,122.51 h176 c-19.89,-35.91 -24,-78.51 -24,-122.51 "
            "V288 h16 a16,16 0,0 0,16 -16 v-32 a16,16 0,0 0,-16 -16 h-25.1 "
            "c29.39,-18.38 49.1,-50.78 49.1,-88 a104,104 0,0 0,-208 0 c0,37.22 "
            "19.71,69.62 49.1,88 zM304,448 L16,448 a16,16 0,0 0,-16 16 v32 a16,16 0,0 "
            "0,16 16 h288 a16,16 0,0 0,16 -16 v-32 a16,16 0,0 0,-16 -16 z "
        ),
    ),
    KNIGHT: (
        384,
        (
            "M19,272.47 l40.63,18.06 a32,32 0,0 0,24.88 0.47 l12.78,-5.12 a32,32 0,0 "
            "0,18.76 -20.5 l9.22,-30.65 a24,24 0,0 1,12.55 -15.65 L159.94,208 v50.33 "
            "a48,48 0,0 1,-26.53 42.94 l-57.22,28.65 A80,80 0,0 0,32 401.48 V416 "
            "h319.86 V224 c0,-106 -85.92,-192 -191.92,-192 H12 A12,12 0,0 0,0 44 "
            "a16.9,16.9 0,0 0,1.79 7.58 L16,80 l-9,9 a24,24 0,0 0,-7 17 v137.21 "
            "a32,32 0,0 0,19 29.26 zM52,128 a20,20 0,1 1,-20 20 a20,20 0,0 1,20 -20 "
            "zM368,448 L16,448 a16,16 0,0 0,-16 16 v32 a16,16 0,0 0,16 16 h352 a16,16 "
            "0,0 0,16 -16 v-32 a16,16 0,0 0,-16 -16 z "
        ),
    ),
    BISHOP: (
        320,
        (
            "M8,287.88 c0,51.64 22.14,73.83 56,84.6 V416 h192 v-43.52 c33.86,-10.77 "
            "56,-33 56,-84.6 c0,-30.61 -10.73,-67.1 -26.69,-102.56 L185,285.65 a8,8 "
            "0,0 1,-11.31 0 l-11.31,-11.31 a8,8 0,0 1,0 -11.31 L270.27,155.1 "
            "c-20.8,-37.91 -46.47,-72.1 -70.87,-92.59 C213.4,59.09 224,47.05 224,32 "
            "a32,32 0,0 0,-32 -32 h-64 a32,32 0,0 0,-32 32 c0,15 10.6,27.09 "
            "24.6,30.51 C67.81,106.8 8,214.5 8,287.88 zM304,448 L16,448 a16,16 0,0 "
            "0,-16 16 v32 a16,16 0,0 0,16 16 h288 a16,16 0,0 0,16 -16 v-32 a16,16 0,0 "
            "0,-16 -16 z "
        ),
    ),
    ROOK: (
        384,
        (
            "M368,32 L312,32 a16,16 0,0 0,-16 16 v48 h-48 V48 a16,16 0,0 0,-16 -16 "
            "h-80 a16,16 0,0 0,-16 16 v48 H88.1 V48 a16,16 0,0 0,-16 -16 H16 A16,16 "
            "0,0 0,0 48 v176 l64,32 c0,48.33 -1.54,95 -13.21,160 h282.42 C321.54,351 "
            "320,303.72 320,256 l64,-32 V48 a16,16 0,0 0,-16 -16 zM224,320 h-64 v-64 "
            "a32,32 0,0 1,64 0 zM368,448 L16,448 a16,16 0,0 0,-16 16 v32 a16,16 0,0 "
            "0,16 16 h352 a16,16 0,0 0,16 -16 v-32 a16,16 0,0 0,-16 -16 z "
        ),
    ),
    QUEEN: (
        512,
        (
            "M256,112 a56,56 0,1 0,-56 -56 a56,56 0,0 0,56 56 zM432,448 L80,448 "
            "a16,16 0,0 0,-16 16 v32 a16,16 0,0 0,16 16 h352 a16,16 0,0 0,16 -16 v-32 "
            "a16,16 0,0 0,-16 -16 zM504.87,184.16 l-28.51,-15.92 c-7.44,-5 "
            "-16.91,-2.46 -22.29,4.68 a47.59,47.59 0,0 1,-47.23 18.23 C383.7,186.86 "
            "368,164.93 368,141.4 a13.4,13.4 0,0 0,-13.4 -13.4 h-38.77 c-6,0 -11.61,4 "
            "-12.86,9.91 a48,48 0,0 1,-93.94 0 c-1.25,-5.92 -6.82,-9.91 -12.86,-9.91 "
            "H157.4 a13.4,13.4 0,0 0,-13.4 13.4 c0,25.69 -19,48.75 -44.67,50.49 "
            "a47.5,47.5 0,0 1,-41.54 -19.15 c-5.28,-7.09 -14.73,-9.45 -22.09,-4.54 "
            "l-28.57,16 a16,16 0,0 0,-5.44 20.47 L104.24,416 h303.52 l102.55,-211.37 "
            "a16,16 0,0 0,-5.44 -20.47 z "
        ),
    ),
    KING: (
        448,
        (
            "M400,448 L48,448 a16,16 0,0 0,-16,16 v32 a16,16 0,0 0,16,16 h352 a16,16 "
            "0,0 0,16,-16 v-32 a16,16 0,0 0,-16,-16 zM416,160 L256,160 v-48 h40 a8,8 "
            "0,0 0,8,-8 V56 a8,8 0,0 0,-8,-8 h-40 V8 a8,8 0,0 0,-8,-8 h-48 a8,8 0,0 "
            "0,-8,8 v40 h-40 a8,8 0,0 0,-8,8 v48 a8,8 0,0 0,8,8 h40 v48 H32 a32,32 "
            "0,0 0,-30.52 41.54 L74.56,416 h298.88 l73.08,-214.46 A32,32 0,0 0,416 "
            "160 z "
        ),
    ),
}

_COMMANDS = "MmZzLlHhVvCcSsQqTtAa"
_SEPARATORS = ", \t\r\n"


class _Reader:
    """A scanner over path data.

    Written by hand rather than as one regular expression for the sake of the
    arc flags: in `a16,16 0 0116,16` the two flags and the following coordinate
    are one run of digits, and a tokeniser that reads numbers would take `0116`
    as a single one. A flag is a character, so it is read as a character. These
    six paths happen to space theirs out, but a reader that only works on the
    input it was written against is a reader that fails the first time anybody
    exports the artwork again.
    """

    def __init__(self, text: str) -> None:
        self.text = text
        self.at = 0

    def _skip(self) -> None:
        while self.at < len(self.text) and self.text[self.at] in _SEPARATORS:
            self.at += 1

    def more(self) -> bool:
        self._skip()
        return self.at < len(self.text)

    def command(self) -> str | None:
        self._skip()
        if self.at < len(self.text) and self.text[self.at] in _COMMANDS:
            self.at += 1
            return self.text[self.at - 1]
        return None

    def number(self) -> float:
        self._skip()
        start = self.at
        text = self.text
        if self.at < len(text) and text[self.at] in "+-":
            self.at += 1
        while self.at < len(text) and (text[self.at].isdigit() or text[self.at] == "."):
            self.at += 1
        if self.at < len(text) and text[self.at] in "eE":
            self.at += 1
            if self.at < len(text) and text[self.at] in "+-":
                self.at += 1
            while self.at < len(text) and text[self.at].isdigit():
                self.at += 1
        if self.at == start:
            raise ValueError(
                f"expected a number at {start} in {text[start : start + 12]!r}"
            )
        return float(text[start : self.at])

    def flag(self) -> bool:
        self._skip()
        char = self.text[self.at]
        self.at += 1
        return char == "1"


def _arc(x0, y0, rx, ry, rotation, large, sweep, x, y) -> list[tuple]:
    """One elliptical arc, as cubic curves.

    Cairo has arcs, but only circular ones on an untransformed axis, and these
    paths draw rounded corners as small ellipse segments. Turning the arc into
    Béziers here -- endpoint form to centre form, then a curve per quarter turn
    -- is the standard conversion, and doing it at import means the drawing
    code never sees an arc at all.
    """
    if (x0, y0) == (x, y):
        return []
    rx, ry = abs(rx), abs(ry)
    if not rx or not ry:
        return [("L", x, y)]
    phi = math.radians(rotation)
    cosine, sine = math.cos(phi), math.sin(phi)
    dx, dy = (x0 - x) / 2, (y0 - y) / 2
    ux = cosine * dx + sine * dy
    uy = -sine * dx + cosine * dy
    stretch = (ux * ux) / (rx * rx) + (uy * uy) / (ry * ry)
    if stretch > 1:
        grow = math.sqrt(stretch)
        rx, ry = rx * grow, ry * grow
    top = rx * rx * ry * ry - rx * rx * uy * uy - ry * ry * ux * ux
    bottom = rx * rx * uy * uy + ry * ry * ux * ux
    scale = math.sqrt(max(top / bottom, 0.0)) * (-1 if large == sweep else 1)
    cx, cy = scale * rx * uy / ry, -scale * ry * ux / rx
    centre_x = cosine * cx - sine * cy + (x0 + x) / 2
    centre_y = sine * cx + cosine * cy + (y0 + y) / 2

    def angle(vx, vy, wx, wy):
        length = math.hypot(vx, vy) * math.hypot(wx, wy)
        if not length:
            return 0.0
        found = math.acos(max(-1.0, min(1.0, (vx * wx + vy * wy) / length)))
        return -found if vx * wy - vy * wx < 0 else found

    start = angle(1, 0, (ux - cx) / rx, (uy - cy) / ry)
    sweep_angle = angle(
        (ux - cx) / rx, (uy - cy) / ry, (-ux - cx) / rx, (-uy - cy) / ry
    )
    if not sweep and sweep_angle > 0:
        sweep_angle -= 2 * math.pi
    elif sweep and sweep_angle < 0:
        sweep_angle += 2 * math.pi

    steps = max(1, math.ceil(abs(sweep_angle) / (math.pi / 2)))
    step = sweep_angle / steps
    reach = 4 / 3 * math.tan(step / 4)
    out = []
    for index in range(steps):
        first, second = start + index * step, start + (index + 1) * step

        def point(theta):
            return (
                centre_x + rx * math.cos(theta) * cosine - ry * math.sin(theta) * sine,
                centre_y + rx * math.cos(theta) * sine + ry * math.sin(theta) * cosine,
            )

        def slope(theta):
            return (
                -rx * math.sin(theta) * cosine - ry * math.cos(theta) * sine,
                -rx * math.sin(theta) * sine + ry * math.cos(theta) * cosine,
            )

        ax, ay = point(first)
        bx, by = point(second)
        adx, ady = slope(first)
        bdx, bdy = slope(second)
        out.append(
            (
                "C",
                ax + reach * adx,
                ay + reach * ady,
                bx - reach * bdx,
                by - reach * bdy,
                bx,
                by,
            )
        )
    return out


def parse(data: str) -> list[tuple]:
    """SVG path data as ("M"|"L"|"C"|"Z", ...) tuples, all absolute."""
    reader = _Reader(data)
    out: list[tuple] = []
    x = y = 0.0
    start_x = start_y = 0.0
    previous = ""
    control_x = control_y = 0.0
    command = ""
    while reader.more():
        found = reader.command()
        if found:
            if not command and found not in ("M", "m"):
                raise ValueError(f"path data begins with {found!r}, not a moveto")
            command = found
        elif command in ("M", "m"):
            # A second coordinate pair after a moveto is a lineto, which is the
            # one place SVG changes the command out from under you.
            command = "L" if command == "M" else "l"
        elif not command:
            raise ValueError("path data does not begin with a command")
        upper = command.upper()
        relative = command.islower()
        if upper == "Z":
            out.append(("Z",))
            x, y = start_x, start_y
        elif upper in ("M", "L"):
            nx, ny = reader.number(), reader.number()
            x, y = (x + nx, y + ny) if relative else (nx, ny)
            out.append((upper, x, y))
            if upper == "M":
                start_x, start_y = x, y
        elif upper == "H":
            nx = reader.number()
            x = x + nx if relative else nx
            out.append(("L", x, y))
        elif upper == "V":
            ny = reader.number()
            y = y + ny if relative else ny
            out.append(("L", x, y))
        elif upper in ("C", "S"):
            if upper == "C":
                x1, y1 = reader.number(), reader.number()
                if relative:
                    x1, y1 = x + x1, y + y1
            else:
                # Smooth: the first control point is the last one reflected,
                # unless the previous command was not a cubic, in which case it
                # is the current point.
                x1, y1 = (
                    (2 * x - control_x, 2 * y - control_y)
                    if previous in "CcSs"
                    else (x, y)
                )
            x2, y2 = reader.number(), reader.number()
            nx, ny = reader.number(), reader.number()
            if relative:
                x2, y2, nx, ny = x + x2, y + y2, x + nx, y + ny
            out.append(("C", x1, y1, x2, y2, nx, ny))
            control_x, control_y, x, y = x2, y2, nx, ny
        elif upper in ("Q", "T"):
            if upper == "Q":
                qx, qy = reader.number(), reader.number()
                if relative:
                    qx, qy = x + qx, y + qy
            else:
                qx, qy = (
                    (2 * x - control_x, 2 * y - control_y)
                    if previous in "QqTt"
                    else (x, y)
                )
            nx, ny = reader.number(), reader.number()
            if relative:
                nx, ny = x + nx, y + ny
            # A quadratic is a cubic whose control points sit two thirds of the
            # way out. Cairo has no quadratic, and this is exact.
            out.append(
                (
                    "C",
                    x + 2 / 3 * (qx - x),
                    y + 2 / 3 * (qy - y),
                    nx + 2 / 3 * (qx - nx),
                    ny + 2 / 3 * (qy - ny),
                    nx,
                    ny,
                )
            )
            control_x, control_y, x, y = qx, qy, nx, ny
        elif upper == "A":
            rx, ry = reader.number(), reader.number()
            rotation = reader.number()
            large, sweep = reader.flag(), reader.flag()
            nx, ny = reader.number(), reader.number()
            if relative:
                nx, ny = x + nx, y + ny
            out.extend(_arc(x, y, rx, ry, rotation, large, sweep, nx, ny))
            x, y = nx, ny
        else:
            raise ValueError(f"unsupported path command {command!r}")
        previous = command
    return out


OUTLINES: dict[int, tuple[float, list[tuple]]] = {
    kind: (float(width), parse(data)) for kind, (width, data) in SOURCES.items()
}


def extent(kind: int) -> tuple[float, float, float, float]:
    """The box a piece's outline actually occupies, for the tests.

    Curves are measured by their control points, which can only ever overstate
    the box -- a Bézier stays inside the hull of its own control points. So an
    outline that fits here fits for real.
    """
    left = top = math.inf
    right = bottom = -math.inf
    for op in OUTLINES[kind][1]:
        for index in range(1, len(op), 2):
            left, right = min(left, op[index]), max(right, op[index])
            top, bottom = min(top, op[index + 1]), max(bottom, op[index + 1])
    return left, top, right, bottom


def path(cr, kind: int, x: float, y: float, size: float) -> None:
    """Lay the piece into the context's current path, filling a square.

    Nothing is filled or stroked here: whoever asked wants to do both, in two
    colours, and a path is the thing both of those need.
    """
    width, outline = OUTLINES[kind]
    scale = size / HEIGHT
    cr.save()
    cr.translate(x + (size - width * scale) / 2, y)
    cr.scale(scale, scale)
    cr.new_sub_path()
    for op in outline:
        if op[0] == "L":
            cr.line_to(op[1], op[2])
        elif op[0] == "C":
            cr.curve_to(op[1], op[2], op[3], op[4], op[5], op[6])
        elif op[0] == "M":
            cr.move_to(op[1], op[2])
        else:
            cr.close_path()
    cr.restore()


NAMES = {
    PAWN: "pawn",
    KNIGHT: "knight",
    BISHOP: "bishop",
    ROOK: "rook",
    QUEEN: "queen",
    KING: "king",
}
