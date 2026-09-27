// The sum that was half typed when the phone took the app away.
//
// One small JSON file, and the argument for it is the argument for the app. A
// desktop calculator is a window you leave open; a phone calculator is a thing
// you are holding when somebody rings, and what happens next is that the
// compositor reclaims the app without asking. Coming back to a blank screen is
// what makes a phone calculator annoying, and the fix is not a setting, it is
// a file with two fields in it.
//
// Both are written as text. `0.1` is one thing in decimal and another once JSON
// has been through a double, and the whole point of the arithmetic here is not
// letting that happen.
//
// `answered` is the second field, and it is stored rather than worked out
// because it cannot be: the entry comes back either from `=` -- in which case
// it is an answer, and the next digit starts a new sum -- or from the window
// going away mid-sum, in which case it is a number being typed and the next
// digit belongs on the end of it. Both look like `1428` in a file.
//
// `tape` is 0.2.0's, and a file without it is an empty tape: every sum `=` has
// answered, newest last, as the text that was typed and the answer as the
// keypad would carry on from it. A file the plugin wrote reads here, and the
// plugin ignores the key it does not know.
.pragma library

var SCHEMA = 1
// Long enough to find the price from ten minutes ago, short enough that the
// file stays a few hundred bytes.
var TAPE = 50

function parse(data) {
  var out = { entry: "", answered: false, tape: [] }
  if (!data || typeof data !== "object") return out
  if (typeof data.entry === "string") out.entry = data.entry
  out.answered = !!data.answered
  if (data.tape && data.tape.constructor === Array) {
    for (var i = 0; i < data.tape.length; i++) {
      var t = data.tape[i]
      if (t && typeof t.sum === "string" && typeof t.answer === "string")
        out.tape.push({ sum: t.sum, answer: t.answer })
    }
    out.tape = out.tape.slice(-TAPE)
  }
  return out
}

function serialize(state) {
  return JSON.stringify({
    schema: SCHEMA,
    entry: String(state.entry || ""),
    answered: !!state.answered,
    tape: (state.tape || []).slice(-TAPE)
  }, null, 1) + "\n"
}

// The tape with one more line on the end. The same sum answered twice in a row
// is one line: pressing `=` again is not a second calculation.
function remember(tape, sum, answer) {
  var out = (tape || []).slice()
  var last = out.length ? out[out.length - 1] : null
  if (last && last.sum === sum && last.answer === answer) return out
  out.push({ sum: sum, answer: answer })
  return out.slice(-TAPE)
}
