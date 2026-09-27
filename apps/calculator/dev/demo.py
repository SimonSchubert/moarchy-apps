#!/usr/bin/python3
"""Write a tape worth photographing into MOARCHY_CALCULATOR_DIR.

A keypad under a zero says nothing. This is the file the app keeps -- the sum
being typed and the tape of answered sums -- with a morning's worth of the
arithmetic a calculator is actually opened for. The sum on the display comes
from the shot's own MOARCHY_CALCULATOR_TYPED, pressed through the keys.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

out = Path(os.environ.get("MOARCHY_CALCULATOR_DIR") or "demo")
out.mkdir(parents=True, exist_ok=True)

tape = [
    {"sum": "0.1+0.2", "answer": "0.3"},
    {"sum": "200+10%", "answer": "220"},
    {"sum": "4.2*3", "answer": "12.6"},
    {"sum": "1/3*3", "answer": "1"},
    {"sum": "(12+3)*4", "answer": "60"},
    {"sum": "86.40/3", "answer": "28.8"},
    {"sum": "1299-15%", "answer": "1104.15"},
]
state = {"schema": 1, "entry": "", "answered": False, "tape": tape}
(out / "calculator.json").write_text(json.dumps(state, indent=1) + "\n", encoding="utf-8")
