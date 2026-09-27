// The rules: six guesses, five letters, and the two-pass colouring.
//
// There is one thing in this file that is not obvious, and it is the only
// thing in this game that implementations get wrong: **duplicate letters**.
//
// The colouring is two passes. The first marks every letter that is in the
// right place and *consumes* that letter from the secret; the second marks a
// letter present only while an unconsumed instance of it remains, and absent
// otherwise. Guess ALLOY against LOYAL and only two of the three Ls may light
// up, because the secret has two.
//
// Ported from the GTK version's fiveletters.py (0.1.0) rule for rule; the same
// logic is in Braincup's WordleGame.kt, where the word lists come from.
.pragma library

var LENGTH = 5
var GUESSES = 6
var ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
var WORD = /^[A-Z]{5}$/

// The rows of the keyboard the app draws for itself.
var KEYBOARD = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]

// What a letter turned out to be. The order is the precedence: a key on the
// keyboard never goes backwards.
var ABSENT = 0
var PRESENT = 1
var CORRECT = 2

function evaluate(guess, secret) {
  var marks = []
  var left = ({})
  for (var i = 0; i < guess.length; i++) marks.push(ABSENT)
  for (var s = 0; s < secret.length; s++) left[secret[s]] = (left[secret[s]] || 0) + 1
  for (var a = 0; a < guess.length; a++) {
    if (a < secret.length && guess[a] === secret[a]) {
      marks[a] = CORRECT
      left[guess[a]] -= 1
    }
  }
  for (var b = 0; b < guess.length; b++) {
    if (marks[b] === CORRECT) continue
    if ((left[guess[b]] || 0) > 0) {
      marks[b] = PRESENT
      left[guess[b]] -= 1
    }
  }
  return marks
}

function right(guess) {
  for (var i = 0; i < guess.marks.length; i++) if (guess.marks[i] !== CORRECT) return false
  return guess.marks.length > 0
}

// Is this a word the game will take? Length first, then the list -- an object
// used as a set, or null for anything five letters long.
function accepts(word, allowed) {
  var w = String(word || "").toUpperCase()
  if (!WORD.test(w)) return false
  if (!allowed) return true
  return allowed[w] === true
}

// One secret and the guesses made at it. The guesses are the state and the
// board is derived from them: a word that will not play is where a saved game
// stops, so a file cannot describe a board play could not reach.
function make(secret, allowed, words) {
  var g = { secret: String(secret).toUpperCase(), allowed: allowed || null, guesses: [] }
  var list = words || []
  for (var i = 0; i < list.length; i++) {
    var next = submit(g, list[i])
    if (next === g) break
    g = next
  }
  return g
}

// A new game with the word added, or the same object when it was refused.
function submit(g, word) {
  if (over(g) || !accepts(word, g.allowed)) return g
  var w = String(word).toUpperCase()
  return {
    secret: g.secret, allowed: g.allowed,
    guesses: g.guesses.concat([{ word: w, marks: evaluate(w, g.secret) }])
  }
}

function solved(g) { return g.guesses.length > 0 && right(g.guesses[g.guesses.length - 1]) }
function out(g) { return g.guesses.length >= GUESSES && !solved(g) }
function over(g) { return solved(g) || out(g) }
function used(g) { return g.guesses.length }
function left(g) { return Math.max(GUESSES - g.guesses.length, 0) }
function words(g) { return g.guesses.map(function (x) { return x.word }) }

// The best thing known about each letter, for colouring the keyboard. Best,
// not latest: a letter shown correct once stays correct.
function keys(g) {
  var out = ({})
  for (var i = 0; i < g.guesses.length; i++) {
    var guess = g.guesses[i]
    for (var j = 0; j < guess.word.length; j++) {
      var l = guess.word[j]
      if (out[l] === undefined || guess.marks[j] > out[l]) out[l] = guess.marks[j]
    }
  }
  return out
}

// The letters placed so far, as a pattern like "CR___". For the tests.
function known(g) {
  var placed = ["_", "_", "_", "_", "_"]
  for (var i = 0; i < g.guesses.length; i++)
    for (var j = 0; j < LENGTH; j++)
      if (g.guesses[i].marks[j] === CORRECT) placed[j] = g.guesses[i].word[j]
  return placed.join("")
}
