import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Calc.js" as Calc
import "Store.js" as S

// A calculator: the four operations, a tape you can tap, and arithmetic in
// tens.
//
//     omarchy-shell shell toggle org.moarchy.calculator
//
// On a phone, two bands. **The keypad is the bottom half**, because it is the
// only part anybody touches and a phone is held from the bottom. **The sum is
// everything above it**, sitting on the keys rather than at the far end of
// the window, so the thing changing is next to the thing changing it. The
// tape is a page behind a button. On a desktop the tape is beside the keys,
// and the whole keyboard types.
//
// The running answer under the expression is why `=` goes unpressed in most
// sessions: it appears as soon as the sum has an operator in it, recomputed on
// every keystroke, which `Calc.complete()` makes affordable.
//
// What is written down is the sum being typed and the tape, and not per
// keystroke -- that is a write per digit onto a phone's flash -- but on `=`
// and when the window goes away. Coming back to a blank screen after taking a
// call is the thing that makes a phone calculator annoying.
App {
  id: root

  appId: "org.moarchy.calculator"
  title: "Calculator"
  windowWidth: 820
  windowHeight: 620

  store: Store { name: "moarchy-calculator" }

  launcher.desktopId: "org.moarchy.Calculator"
  launcher.genericName: "Calculator"
  launcher.comment: "The four operations, a tape you can tap, and arithmetic in tens"
  launcher.categories: "Utility;Calculator;"
  launcher.keywords: "calculator;calc;maths;math;arithmetic;sum;percent;tape;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  actions: Component {
    Row {
      IconButton {
        visible: root.compact
        app: root
        glyph: KG.history
        label: "Tape"
        onClicked: root.push({ kind: "tape" })
      }
    }
  }

  page: Component {
    Item {
      PageHeader { id: tapeHead; app: root; width: parent.width; title: "Tape" }
      Tape {
        anchors.top: tapeHead.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.ui.gutter
        app: root
        titled: false
        tape: root.tape
        onPicked: function (answer) { root.use(answer); root.back() }
        onCleared: root.clearTape()
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "The four operations, a tape you can tap, and arithmetic that counts in tens."
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["0 – 9  .  ,", "Digits and the point"],
          ["+ − * / %", "Operators and per cent"],
          ["( )", "Brackets"],
          ["Enter  =", "Answer"],
          ["Backspace", "Take back a key"],
          ["Delete", "Clear"],
          ["Esc", "Clear, then back"],
          ["Ctrl+C  Ctrl+V", "Copy the answer, paste a number"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "It counts in tens"
        note: "Every sum is worked in decimal to thirty digits and shown to twelve, so 0.1 + 0.2 is 0.3 and 1 ÷ 3 × 3 is 1. The sum being typed and the tape are kept in ~/.local/share/moarchy-calculator/calculator.json."
      }
    }
  }

  // ------------------------------------------------------------ the sum

  // The sum being typed. One string, and Calc.js holds every function allowed
  // to change it -- which is what makes it impossible to type something that
  // will not evaluate.
  property string entry: ""
  // The display shows an answer rather than something being typed: the next
  // digit starts a new sum and the next operator carries on from this one.
  property bool answered: false
  // A sentence where the running answer goes, when the sum cannot have one.
  property string problem: ""
  property var tape: []
  property bool restored: false

  readonly property string shownSum: entry.length ? Calc.pretty(entry) : "0"
  // The running answer, or nothing while the sum is a single number: `12`
  // under `12` is a line spent saying that twelve is twelve.
  readonly property string shownAnswer: {
    if (problem.length) return problem
    var ready = Calc.complete(entry)
    if (!ready.length || Calc.isPlain(ready)) return ""
    var value = Calc.running(entry)
    return value === null ? "" : Calc.formatNumber(value)
  }

  function press(token) {
    if (token === "=") { equals(); return }
    if (token === "AC") { clearSum(); return }
    var text = entry
    // Backspacing an answer would delete a digit of a number the display is
    // showing rounded, an edit nobody could see. It clears instead, as a
    // fresh digit does.
    if (answered && (token === "<" || token === "()" || token === "." || Calc.isDigit(token))) text = ""
    answered = false
    problem = ""
    if (Calc.isDigit(token)) text = Calc.digit(text, token)
    else if (token === ".") text = Calc.point(text)
    else if (Calc.isOperator(token)) text = Calc.operator(text, token)
    else if (token === "()") text = Calc.bracket(text)
    else if (token === "%") text = Calc.percent(text)
    else if (token === "<") text = Calc.back(text)
    entry = text
  }

  // `=` replaces the sum with its answer, kept to the digit rather than to
  // the twelve the display shows, and writes the pair on the tape.
  function equals() {
    var ready = Calc.complete(entry)
    if (!ready.length) return
    var answer = Calc.evaluate(ready)
    if (!answer.ok) { problem = answer.why; return }
    var value = Calc.toEntry(answer.value)
    if (!Calc.isPlain(ready)) tape = S.remember(tape, ready, value)
    entry = value
    answered = true
    problem = ""
    save()
  }

  function clearSum() {
    problem = ""
    answered = false
    entry = ""
  }

  // A line of the tape, back on the display as an answer to carry on from.
  function use(answer) {
    entry = answer
    answered = true
    problem = ""
  }

  function clearTape() {
    var was = tape
    tape = []
    save()
    toast("Tape cleared", "Undo", function () { root.tape = was; root.save() })
  }

  // A run of keys, pressed one at a time rather than assigned: the
  // screenshots', the IPC handler's and a paste's way in, so none of them can
  // reach a state the keypad cannot.
  function keysFrom(text) {
    var source = String(text || "")
    for (var i = 0; i < source.length; i++) {
      var ch = source.charAt(i)
      if (ch === "(" || ch === ")") press("()")
      else if (ch === ",") continue
      else if (ch === "x" || ch === "×") press("*")
      else if (ch === "÷") press("/")
      else if (ch === "−") press("-")
      else press(ch)
    }
  }

  function save() {
    file.save(S.serialize({ entry: entry, answered: answered, tape: tape }))
  }

  DataFile {
    id: file
    app: "calculator"
    name: "calculator.json"
    // Read once, at startup, and never again. Not an optimisation: a save
    // fires the watch, and the reload would put the answer back on the
    // display a moment after somebody started typing the next sum.
    onParsed: function (data) {
      if (root.restored) return
      root.restored = true
      var state = S.parse(data)
      root.entry = state.entry
      root.answered = state.answered
      root.tape = state.tape
      // MOARCHY_CALCULATOR_TYPED: keys to press on arrival, for the
      // screenshots and for anybody who wants to see a particular sum.
      var typed = Quickshell.env("MOARCHY_CALCULATOR_TYPED") || ""
      if (typed.length) root.keysFrom(typed)
      root.wantTape = Quickshell.env("MOARCHY_CALCULATOR_PAGE") === "tape"
      Qt.callLater(root.showTape)
    }
    onQuarantined: function (to) { root.toast("The saved sum was unreadable and was kept aside") }
  }

  // The tape is beside the keys on a desktop and a page on a phone, and the
  // window's width is not known in the first frame.
  property bool wantTape: false
  function showTape() {
    if (!wantTape || !compact) return
    wantTape = false
    push({ kind: "tape" })
  }
  onCompactChanged: showTape()

  // The one write that matters: whatever was being typed when the window went
  // away.
  onOpenedChanged: if (!opened && restored) save()

  // Escape clears a sum before it leaves, on a keyboard. The phone's back
  // gesture does not: a sum is what the app is kept for, and a swipe that
  // threw it away would be the annoying calculator this is not.
  stepBack: function () {
    if (!compact && (entry.length || problem.length)) { clearSum(); return true }
    return false
  }

  // A hidden field for the clipboard, which Qt reaches through text editing.
  TextInput { id: clip; visible: false }

  keyHandler: function (event) {
    if (topPage || inSettings) return
    if (event.modifiers & Qt.ControlModifier) {
      if (event.key === Qt.Key_C) {
        var value = Calc.running(entry)
        clip.text = value === null ? "" : Calc.formatNumber(value, false)
        clip.selectAll()
        clip.copy()
        if (clip.text) toast("Copied " + clip.text)
        event.accepted = true
      } else if (event.key === Qt.Key_V) {
        clip.text = ""
        clip.paste()
        keysFrom(clip.text.replace(/\s/g, ""))
        event.accepted = true
      }
      return
    }
    if (event.modifiers & (Qt.AltModifier | Qt.MetaModifier)) return
    var k = event.key
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { press("="); event.accepted = true; return }
    if (k === Qt.Key_Backspace) { press("<"); event.accepted = true; return }
    if (k === Qt.Key_Delete) { press("AC"); event.accepted = true; return }
    var ch = String(event.text || "")
    if (!ch.length) return
    if (Calc.isDigit(ch) || Calc.isOperator(ch) || ch === "%" || ch === "=") { press(ch); event.accepted = true; return }
    if (ch === "x") { press("*"); event.accepted = true; return }
    // The decimal point is a point; a comma is the same key, for a keypad
    // whose locale puts one there.
    if (ch === "." || ch === ",") { press("."); event.accepted = true; return }
    if (ch === "(" || ch === ")") { press("()"); event.accepted = true }
  }

  IpcHandler {
    target: "calculator"
    // One key at a time, named as the keypad names it, so a script drives the
    // app through exactly the path a thumb does.
    function key(token: string): string { root.press(String(token)); return root.entry }
    function keys(tokens: string): string { root.keysFrom(tokens); return root.entry }
    function sum(): string { return root.entry }
    function answer(): string { return root.shownAnswer }
  }

  // ------------------------------------------------------------ the screen

  // Phone: the sum against the top of the keypad, the keypad against the
  // bottom of the window.
  Item {
    anchors.fill: parent
    visible: root.compact

    Keypad {
      id: phoneKeys
      app: root
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: root.ui.gutter
      onPressed: function (token) { root.press(token) }
    }
    Display {
      app: root
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: phoneKeys.top
      anchors.leftMargin: root.ui.gutter
      anchors.rightMargin: root.ui.gutter
      anchors.bottomMargin: 12
      sum: root.shownSum
      answer: root.shownAnswer
      problem: root.problem.length > 0
    }
  }

  // Desktop: the display and the keys on the left, the tape beside them.
  Item {
    anchors.fill: parent
    visible: !root.compact

    // The display takes whatever height the keys leave, with the sum at its
    // foot, against the keys, as on a phone.
    Item {
      id: deskLeft
      x: 24
      anchors.top: parent.top
      anchors.topMargin: 8
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 24
      width: Math.min(420, parent.width * 0.55)
      Display {
        app: root
        anchors.top: parent.top
        anchors.bottom: deskKeys.top
        anchors.bottomMargin: 14
        width: parent.width
        sumSize: 44
        sum: root.shownSum
        answer: root.shownAnswer
        problem: root.problem.length > 0
      }
      Keypad {
        id: deskKeys
        app: root
        anchors.bottom: parent.bottom
        width: parent.width
        keyHeight: 56
        onPressed: function (token) { root.press(token) }
      }
    }
    Tape {
      anchors.left: deskLeft.right
      anchors.leftMargin: 24
      anchors.right: parent.right
      anchors.rightMargin: 24
      anchors.top: parent.top
      anchors.topMargin: 8
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 24
      app: root
      tape: root.tape
      onPicked: function (answer) { root.use(answer) }
      onCleared: root.clearTape()
    }
  }
}
