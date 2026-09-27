// The rules of Breakout: a ball, a bat, and a wall written as art.
//
// Ported from the GTK version's breakout.py (0.1.0), constant for constant, and
// checked against its tests. This is the only game here with a clock in it
// rather than a clock on it: the state is continuous, the app advances it once
// a frame, and the whole file is about making that advance correct rather than
// merely fast.
//
// **The world is measured in widths, not pixels.** The field is one unit
// across and HEIGHT units tall, so every speed, size and radius is a fraction
// of the screen, and the game plays identically on a 360 px phone and a
// desktop window. The view's only job is to multiply by one number.
//
// **The ball is stepped in slices small enough that it cannot pass through
// anything.** A ball moving at one width a second crosses a brick in under two
// frames, so a single step per frame tunnels through the wall at exactly the
// moments that matter. advance() cuts the time into slices no longer than it
// takes the ball to travel its own radius.
//
// A world is a plain object, and advance() changes it in place: it is stepped
// sixty times a second, and a new object per frame is a new object per frame.
// Everything around it -- the levels, the rectangles, the constants -- is
// fixed. Nothing here touches QML.
.pragma library

var WIDTH = 1.0
var HEIGHT = 1.62

var COLUMNS = 7
var ROWS = 8

var BRICK_W = WIDTH / COLUMNS
var BRICK_H = 0.060
// Where the wall starts, leaving room above it.
var WALL_TOP = 0.11

var BALL = 0.020
var BAT_W = 0.20
var BAT_H = 0.028
var BAT_Y = HEIGHT - 0.075

// How fast the ball starts, and how much faster each broken brick makes it --
// capped, because a ball at four widths a second is one nobody can follow.
var SPEED = 0.95
var SPEED_STEP = 0.006
var SPEED_MAX = 1.55

// How far from straight up the ball may leave the bat, at its very edge.
var BAT_ANGLE = 62 * Math.PI / 180
// ...and the shallowest it may ever travel, so it never finds a horizontal
// groove between two walls and stays there.
var FLATTEST = 14 * Math.PI / 180

var LIVES = 3

// What a brick is worth: more for the ones that took more hitting.
var SCORE = [0, 10, 25, 45]

// How long the ball waits on the bat before it may be launched. Long enough
// that the tap which ended the last life does not launch the next one.
var SERVE_WAIT = 0.35

// What a step did, for the view to react to.
var HIT_WALL = "wall"
var HIT_BAT = "bat"
var HIT_BRICK = "brick"
var LOST_BALL = "lost"
var CLEARED = "cleared"

// The walls, as art: a digit is a brick and how many hits it takes, a dot is
// a gap. Somebody adding a level should be able to draw one.
var LEVELS = [
  { key: "opening", label: "Opening", art: [
    "1111111",
    "1111111",
    "1111111",
    ".11111.",
    "..111.."] },
  { key: "arch", label: "Arch", art: [
    "..222..",
    ".22222.",
    "2222222",
    "1111111",
    "1111111",
    "1111111"] },
  { key: "gate", label: "Gate", art: [
    "2222222",
    "2.....2",
    "2.111.2",
    "2.111.2",
    "2.111.2",
    "2.....2",
    "2111112"] },
  { key: "chevron", label: "Chevron", art: [
    "3.....3",
    "23...32",
    "123.321",
    ".12321.",
    "..232..",
    "...3..."] },
  { key: "keep", label: "Keep", art: [
    "3333333",
    "3.....3",
    "3.222.3",
    "3.2.2.3",
    "3.222.3",
    "3.....3",
    "3111113"] }
]

// The wall as one integer per cell: how many hits it has left.
function bricksOf(level) {
  var out = []
  for (var i = 0; i < COLUMNS * ROWS; i++) out.push(0)
  var rows = level.art.filter(function (line) { return line.trim() !== "" })
  for (var r = 0; r < Math.min(rows.length, ROWS); r++) {
    for (var c = 0; c < Math.min(rows[r].length, COLUMNS); c++) {
      var g = rows[r][c]
      if (g >= "1" && g <= "9") out[r * COLUMNS + c] = Math.min(parseInt(g, 10), SCORE.length - 1)
    }
  }
  return out
}

// The level for a round number, wrapping round for anybody who gets there:
// five walls and then the first again, faster.
function levelAt(number) {
  var n = Math.max(number || 0, 0)
  return LEVELS[n % LEVELS.length]
}

function brickRect(cell) {
  var row = Math.floor(cell / COLUMNS), column = cell % COLUMNS
  return { x: column * BRICK_W, y: WALL_TOP + row * BRICK_H, w: BRICK_W, h: BRICK_H }
}

function world(level, lives) {
  var bricks = bricksOf(level)
  return {
    level: level,
    bricks: bricks,
    // What each brick started as: what it is worth, whichever hit ends it.
    strength: bricks.slice(),
    lives: lives === undefined ? LIVES : lives,
    score: 0,
    bat: WIDTH / 2,
    speed: SPEED,
    waiting: SERVE_WAIT,
    ballX: WIDTH / 2,
    ballY: BAT_Y - BALL - BAT_H / 2,
    ballVx: 0,
    ballVy: 0,
    served: false
  }
}

function standing(w) {
  var n = 0
  for (var i = 0; i < w.bricks.length; i++) if (w.bricks[i]) n += 1
  return n
}
function cleared(w) { return standing(w) === 0 }
function dead(w) { return w.lives <= 0 }
// Is the ball on the bat, waiting to be sent off?
function ready(w) { return !w.served && w.waiting <= 0 }

// The next wall, with the score, the lives and the speed brought over.
function carryOn(w, level) {
  var next = world(level, w.lives)
  next.score = w.score
  next.speed = w.speed
  next.bat = w.bat
  next.ballX = w.bat
  return next
}

// Put the middle of the bat here, clamped to the field. The bat follows a
// finger absolutely, from anywhere on the field: a thumb covers the bat, so
// the only playable arrangement is the thumb elsewhere and the bat where it
// points.
function aim(w, x) {
  var half = BAT_W / 2
  w.bat = Math.min(Math.max(x, half), WIDTH - half)
  if (!w.served) w.ballX = w.bat
}

// Send the ball off the bat. Ignored until the pause has run out.
function serve(w) {
  if (w.served || w.waiting > 0) return false
  // Up and slightly towards the middle, so the first shot is never the one
  // that goes straight up and comes straight back down forever.
  var lean = (WIDTH / 2 - w.bat) * 0.8
  var angle = Math.atan2(lean, 1.0)
  w.ballVx = Math.sin(angle) * w.speed
  w.ballVy = -Math.cos(angle) * w.speed
  w.served = true
  return true
}

function bounce() { return { events: [], broken: [], scored: 0 } }

// Move the world on by this much time. Returns what happened.
function advance(w, seconds) {
  var b = bounce()
  if (dead(w)) return b
  if (!w.served) {
    w.waiting = Math.max(w.waiting - seconds, 0)
    w.ballX = w.bat
    w.ballY = BAT_Y - BALL - BAT_H / 2
    return b
  }
  var speed = Math.sqrt(w.ballVx * w.ballVx + w.ballVy * w.ballVy) || w.speed
  var slice = BALL / Math.max(speed, 1e-6)
  var left = seconds
  // A hard cap, so a frame the compositor lost -- a phone waking with two
  // seconds on the clock -- cannot become a thousand steps in one repaint.
  for (var i = 0; i < 240; i++) {
    if (left <= 0) break
    var step = Math.min(left, slice)
    stepOnce(w, step, b)
    left -= step
    if (b.events.indexOf(LOST_BALL) >= 0 || b.events.indexOf(CLEARED) >= 0) break
  }
  return b
}

function stepOnce(w, seconds, b) {
  w.ballX += w.ballVx * seconds
  w.ballY += w.ballVy * seconds

  if (w.ballX < BALL) {
    w.ballX = BALL
    w.ballVx = Math.abs(w.ballVx)
    b.events.push(HIT_WALL)
  } else if (w.ballX > WIDTH - BALL) {
    w.ballX = WIDTH - BALL
    w.ballVx = -Math.abs(w.ballVx)
    b.events.push(HIT_WALL)
  }
  if (w.ballY < BALL) {
    w.ballY = BALL
    w.ballVy = Math.abs(w.ballVy)
    b.events.push(HIT_WALL)
  }

  hitBricks(w, b)
  hitBat(w, b)

  if (w.ballY > HEIGHT + BALL) {
    w.lives -= 1
    w.served = false
    w.waiting = SERVE_WAIT
    w.ballX = w.bat
    w.ballY = BAT_Y - BALL - BAT_H / 2
    w.ballVx = 0
    w.ballVy = 0
    b.events.push(LOST_BALL)
  }
}

function hitBat(w, b) {
  if (w.ballVy <= 0) return  // going up: the bat is behind it
  var top = BAT_Y - BAT_H / 2
  if (!(top - BALL <= w.ballY && w.ballY <= BAT_Y + BAT_H / 2 + BALL)) return
  var half = BAT_W / 2
  if (!(w.bat - half - BALL <= w.ballX && w.ballX <= w.bat + half + BALL)) return
  // Where on the bat it landed decides where it goes: the middle sends it
  // back up, the ends out at an angle. That is the whole of the skill.
  var offset = Math.max(Math.min((w.ballX - w.bat) / half, 1), -1)
  var angle = offset * BAT_ANGLE
  w.speed = Math.min(w.speed, SPEED_MAX)
  w.ballVx = Math.sin(angle) * w.speed
  w.ballVy = -Math.cos(angle) * w.speed
  w.ballY = top - BALL
  unflatten(w)
  b.events.push(HIT_BAT)
}

function hitBricks(w, b) {
  var cell = brickAt(w, w.ballX, w.ballY)
  if (cell < 0) return
  var r = brickRect(cell)
  // Bounce off the face the ball is least far through: the cheap version of
  // "where did it come from", right whenever it is not exactly at a corner.
  var fromLeft = Math.abs(w.ballX - r.x)
  var fromRight = Math.abs(r.x + r.w - w.ballX)
  var fromTop = Math.abs(w.ballY - r.y)
  var fromBottom = Math.abs(r.y + r.h - w.ballY)
  if (Math.min(fromLeft, fromRight) < Math.min(fromTop, fromBottom)) {
    w.ballVx = -w.ballVx
    w.ballX += w.ballVx * 1e-3
  } else {
    w.ballVy = -w.ballVy
    w.ballY += w.ballVy * 1e-3
  }

  w.bricks[cell] -= 1
  b.events.push(HIT_BRICK)
  if (w.bricks[cell] <= 0) {
    w.bricks[cell] = 0
    b.broken.push(cell)
    var gained = SCORE[w.strength[cell]]
    w.score += gained
    b.scored += gained
    w.speed = Math.min(w.speed + SPEED_STEP, SPEED_MAX)
    rescale(w)
  }
  if (cleared(w)) b.events.push(CLEARED)
}

function brickAt(w, x, y) {
  if (y < WALL_TOP || y > WALL_TOP + ROWS * BRICK_H) return -1
  var column = Math.floor(x / BRICK_W)
  var row = Math.floor((y - WALL_TOP) / BRICK_H)
  if (!(column >= 0 && column < COLUMNS && row >= 0 && row < ROWS)) return -1
  var cell = row * COLUMNS + column
  return w.bricks[cell] ? cell : -1
}

// Keep the ball's direction and give it the current speed.
function rescale(w) {
  var length = Math.sqrt(w.ballVx * w.ballVx + w.ballVy * w.ballVy)
  if (length <= 0) return
  w.ballVx = w.ballVx / length * w.speed
  w.ballVy = w.ballVy / length * w.speed
}

// Refuse to travel too close to horizontal. A guard: the bat's own limit
// keeps the ball far steeper than this, so it fires only if BAT_ANGLE is ever
// raised -- and what it prevents is a ball crossing the screen for a minute,
// which is not a rally, it is a screensaver.
function unflatten(w) {
  var angle = Math.atan2(w.ballVy, w.ballVx)
  if (Math.abs(Math.sin(angle)) >= Math.sin(FLATTEST)) return
  var sign = w.ballVy <= 0 ? -1 : 1
  var lean = Math.cos(FLATTEST) * (w.ballVx < 0 ? -1 : 1)
  w.ballVx = lean * w.speed
  w.ballVy = sign * Math.sin(FLATTEST) * w.speed
}
