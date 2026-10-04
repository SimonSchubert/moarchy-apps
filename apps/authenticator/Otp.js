// Time-based one-time codes (RFC 6238), and everything between a QR code and
// one: base32, the three hashes, HMAC, the otpauth:// link and Google
// Authenticator's export.
//
// QML has Qt.md5 and nothing else, so the hashes are here, in plain
// JavaScript. They are not fast and do not need to be: a screen of codes is
// one HMAC per account every thirty seconds. tests/tst_otp.qml checks them
// against RFC 6238's own table, which is the only proof that matters -- a code
// that is wrong in one digit is a login that fails with no hint why.
//
// An account is a plain object:
//
//   { id, issuer, name, secret, algorithm, digits, period }
//
// `secret` is base32 as people see it -- upper case, no padding, no spaces --
// because that is what the file shows a person and what a link carries.
.pragma library

var ALGORITHMS = ["SHA1", "SHA256", "SHA512"]
var DIGITS = [6, 7, 8]
var DEFAULT_PERIOD = 30
var MAX_PERIOD = 3600
// A shorter key than this is a typo, not a secret: RFC 4226 asks for 16
// bytes and the shortest anybody issues is 10. Five catches "abc".
var MIN_SECRET_BYTES = 5

// ------------------------------------------------------------ base32

var B32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

// What a person typed or pasted, as the secret would be stored: spaces,
// dashes and padding gone, upper case. Not checked.
function cleanSecret(text) {
  return String(text || "").replace(/[\s\-=]/g, "").toUpperCase()
}

// Bytes, or null when a character is not base32.
function base32Decode(text) {
  var s = cleanSecret(text)
  var out = []
  var bits = 0
  var value = 0
  for (var i = 0; i < s.length; i++) {
    var v = B32.indexOf(s.charAt(i))
    if (v < 0) return null
    value = (value << 5) | v
    bits += 5
    if (bits >= 8) {
      bits -= 8
      out.push((value >>> bits) & 255)
    }
  }
  return out
}

function base32Encode(bytes) {
  var out = ""
  var bits = 0
  var value = 0
  for (var i = 0; i < bytes.length; i++) {
    value = ((value << 8) | bytes[i]) & 0xffff
    bits += 8
    while (bits >= 5) {
      bits -= 5
      out += B32.charAt((value >>> bits) & 31)
    }
  }
  if (bits > 0) out += B32.charAt((value << (5 - bits)) & 31)
  return out
}

// Why a secret will not do, or "" when it will.
function secretProblem(text) {
  var s = cleanSecret(text)
  if (s === "") return "No key"
  var bytes = base32Decode(s)
  if (bytes === null) return "A key is letters A to Z and digits 2 to 7"
  if (bytes.length < MIN_SECRET_BYTES) return "Too short for a key"
  return ""
}

// ------------------------------------------------------------ hashes

function utf8(text) {
  var s = String(text)
  var out = []
  for (var i = 0; i < s.length; i++) {
    var c = s.codePointAt(i)
    if (c > 0xffff) i++
    if (c < 0x80) out.push(c)
    else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63))
    else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63))
    else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63))
  }
  return out
}

function fromUtf8(bytes) {
  var out = ""
  for (var i = 0; i < bytes.length; i++) {
    var b = bytes[i]
    var c = b
    var more = 0
    if (b >= 0xf0) { c = b & 7; more = 3 }
    else if (b >= 0xe0) { c = b & 15; more = 2 }
    else if (b >= 0xc0) { c = b & 31; more = 1 }
    for (var k = 0; k < more && i + 1 < bytes.length; k++) c = (c << 6) | (bytes[++i] & 63)
    out += String.fromCodePoint(c)
  }
  return out
}

// The message padded to whole blocks, its length in bits at the end.
function pad(bytes, block, lengthBytes) {
  var m = bytes.slice()
  var bits = bytes.length * 8
  m.push(0x80)
  while (m.length % block !== block - lengthBytes) m.push(0)
  for (var i = 0; i < lengthBytes - 8; i++) m.push(0)
  var hi = Math.floor(bits / 4294967296)
  var lo = bits >>> 0
  m.push((hi >>> 24) & 255, (hi >>> 16) & 255, (hi >>> 8) & 255, hi & 255)
  m.push((lo >>> 24) & 255, (lo >>> 16) & 255, (lo >>> 8) & 255, lo & 255)
  return m
}

function word(m, i) { return ((m[i] << 24) | (m[i + 1] << 16) | (m[i + 2] << 8) | m[i + 3]) | 0 }

function wordsToBytes(words) {
  var out = []
  for (var i = 0; i < words.length; i++)
    out.push((words[i] >>> 24) & 255, (words[i] >>> 16) & 255, (words[i] >>> 8) & 255, words[i] & 255)
  return out
}

function rotl(x, n) { return (x << n) | (x >>> (32 - n)) }
function rotr(x, n) { return (x >>> n) | (x << (32 - n)) }

function sha1(bytes) {
  var h = [0x67452301, 0xefcdab89 | 0, 0x98badcfe | 0, 0x10325476, 0xc3d2e1f0 | 0]
  var m = pad(bytes, 64, 8)
  var w = new Array(80)
  for (var off = 0; off < m.length; off += 64) {
    for (var t = 0; t < 16; t++) w[t] = word(m, off + t * 4)
    for (t = 16; t < 80; t++) w[t] = rotl(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], 1)
    var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4]
    for (t = 0; t < 80; t++) {
      var f, k
      if (t < 20) { f = (b & c) | (~b & d); k = 0x5a827999 }
      else if (t < 40) { f = b ^ c ^ d; k = 0x6ed9eba1 }
      else if (t < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc | 0 }
      else { f = b ^ c ^ d; k = 0xca62c1d6 | 0 }
      var tmp = (rotl(a, 5) + f + e + k + w[t]) | 0
      e = d; d = c; c = rotl(b, 30); b = a; a = tmp
    }
    h[0] = (h[0] + a) | 0; h[1] = (h[1] + b) | 0; h[2] = (h[2] + c) | 0
    h[3] = (h[3] + d) | 0; h[4] = (h[4] + e) | 0
  }
  return wordsToBytes(h)
}

// SHA-512's eighty round constants, as hex. The first 32 bits of the first
// sixty-four are SHA-256's, which is where SHA-256 takes them from below:
// one table typed once, and checked twice by the tests.
var K512_HEX = [
  "428a2f98d728ae22", "7137449123ef65cd", "b5c0fbcfec4d3b2f", "e9b5dba58189dbbc",
  "3956c25bf348b538", "59f111f1b605d019", "923f82a4af194f9b", "ab1c5ed5da6d8118",
  "d807aa98a3030242", "12835b0145706fbe", "243185be4ee4b28c", "550c7dc3d5ffb4e2",
  "72be5d74f27b896f", "80deb1fe3b1696b1", "9bdc06a725c71235", "c19bf174cf692694",
  "e49b69c19ef14ad2", "efbe4786384f25e3", "0fc19dc68b8cd5b5", "240ca1cc77ac9c65",
  "2de92c6f592b0275", "4a7484aa6ea6e483", "5cb0a9dcbd41fbd4", "76f988da831153b5",
  "983e5152ee66dfab", "a831c66d2db43210", "b00327c898fb213f", "bf597fc7beef0ee4",
  "c6e00bf33da88fc2", "d5a79147930aa725", "06ca6351e003826f", "142929670a0e6e70",
  "27b70a8546d22ffc", "2e1b21385c26c926", "4d2c6dfc5ac42aed", "53380d139d95b3df",
  "650a73548baf63de", "766a0abb3c77b2a8", "81c2c92e47edaee6", "92722c851482353b",
  "a2bfe8a14cf10364", "a81a664bbc423001", "c24b8b70d0f89791", "c76c51a30654be30",
  "d192e819d6ef5218", "d69906245565a910", "f40e35855771202a", "106aa07032bbd1b8",
  "19a4c116b8d2d0c8", "1e376c085141ab53", "2748774cdf8eeb99", "34b0bcb5e19b48a8",
  "391c0cb3c5c95a63", "4ed8aa4ae3418acb", "5b9cca4f7763e373", "682e6ff3d6b2b8a3",
  "748f82ee5defb2fc", "78a5636f43172f60", "84c87814a1f0ab72", "8cc702081a6439ec",
  "90befffa23631e28", "a4506cebde82bde9", "bef9a3f7b2c67915", "c67178f2e372532b",
  "ca273eceea26619c", "d186b8c721c0c207", "eada7dd6cde0eb1e", "f57d4f7fee6ed178",
  "06f067aa72176fba", "0a637dc5a2c898a6", "113f9804bef90dae", "1b710b35131c471b",
  "28db77f523047d84", "32caab7b40c72493", "3c9ebe0a15c9bebc", "431d67c49c100d4c",
  "4cc5d4becb3e42b6", "597f299cfc657e2a", "5fcb6fab3ad6faec", "6c44198c4a475817"
]
var IV512_HEX = [
  "6a09e667f3bcc908", "bb67ae8584caa73b", "3c6ef372fe94f82b", "a54ff53a5f1d36f1",
  "510e527fade682d1", "9b05688c2b3e6c1f", "1f83d9abfb41bd6b", "5be0cd19137e2179"
]

function hiOf(hex) { return parseInt(hex.slice(0, 8), 16) | 0 }
function loOf(hex) { return parseInt(hex.slice(8), 16) | 0 }

var K512_HI = K512_HEX.map(hiOf)
var K512_LO = K512_HEX.map(loOf)
var K256 = K512_HI.slice(0, 64)

function sha256(bytes) {
  var h = IV512_HEX.map(hiOf)
  var m = pad(bytes, 64, 8)
  var w = new Array(64)
  for (var off = 0; off < m.length; off += 64) {
    for (var t = 0; t < 16; t++) w[t] = word(m, off + t * 4)
    for (t = 16; t < 64; t++) {
      var s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >>> 3)
      var s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >>> 10)
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) | 0
    }
    var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
    for (t = 0; t < 64; t++) {
      var t1 = (hh + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + K256[t] + w[t]) | 0
      var t2 = ((rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) | 0
      hh = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0
    }
    h[0] = (h[0] + a) | 0; h[1] = (h[1] + b) | 0; h[2] = (h[2] + c) | 0; h[3] = (h[3] + d) | 0
    h[4] = (h[4] + e) | 0; h[5] = (h[5] + f) | 0; h[6] = (h[6] + g) | 0; h[7] = (h[7] + hh) | 0
  }
  return wordsToBytes(h)
}

// SHA-512 in pairs of 32-bit halves, since JavaScript has no 64-bit integer
// QML can count on. `hi` and `lo` are signed 32-bit; sums are carried by hand.

// Rotations right by n, 0 < n < 64 and n !== 32: the pair [hi, lo].
function rotr64(hi, lo, n) {
  if (n > 32) { var t = hi; hi = lo; lo = t; n -= 32 }
  return [(hi >>> n) | (lo << (32 - n)), (lo >>> n) | (hi << (32 - n))]
}
function shr64(hi, lo, n) {
  return [hi >>> n, (lo >>> n) | (hi << (32 - n))]
}

// The sum of any number of [hi, lo] pairs, mod 2^64.
function add64() {
  var lo = 0
  var hi = 0
  for (var i = 0; i < arguments.length; i++) {
    lo += arguments[i][1] >>> 0
    hi += arguments[i][0] >>> 0
  }
  hi += Math.floor(lo / 4294967296)
  return [hi | 0, lo | 0]
}

function xor3(a, b, c) { return [a[0] ^ b[0] ^ c[0], a[1] ^ b[1] ^ c[1]] }

function sha512(bytes) {
  var h = IV512_HEX.map(function (x) { return [hiOf(x), loOf(x)] })
  var m = pad(bytes, 128, 16)
  var w = new Array(80)
  for (var off = 0; off < m.length; off += 128) {
    for (var t = 0; t < 16; t++) w[t] = [word(m, off + t * 8), word(m, off + t * 8 + 4)]
    for (t = 16; t < 80; t++) {
      var x = w[t - 15], y = w[t - 2]
      var s0 = xor3(rotr64(x[0], x[1], 1), rotr64(x[0], x[1], 8), shr64(x[0], x[1], 7))
      var s1 = xor3(rotr64(y[0], y[1], 19), rotr64(y[0], y[1], 61), shr64(y[0], y[1], 6))
      w[t] = add64(w[t - 16], s0, w[t - 7], s1)
    }
    var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
    for (t = 0; t < 80; t++) {
      var S1 = xor3(rotr64(e[0], e[1], 14), rotr64(e[0], e[1], 18), rotr64(e[0], e[1], 41))
      var ch = [(e[0] & f[0]) ^ (~e[0] & g[0]), (e[1] & f[1]) ^ (~e[1] & g[1])]
      var t1 = add64(hh, S1, ch, [K512_HI[t], K512_LO[t]], w[t])
      var S0 = xor3(rotr64(a[0], a[1], 28), rotr64(a[0], a[1], 34), rotr64(a[0], a[1], 39))
      var maj = [(a[0] & b[0]) ^ (a[0] & c[0]) ^ (b[0] & c[0]), (a[1] & b[1]) ^ (a[1] & c[1]) ^ (b[1] & c[1])]
      var t2 = add64(S0, maj)
      hh = g; g = f; f = e; e = add64(d, t1); d = c; c = b; b = a; a = add64(t1, t2)
    }
    var regs = [a, b, c, d, e, f, g, hh]
    for (var r = 0; r < 8; r++) h[r] = add64(h[r], regs[r])
  }
  var out = []
  for (var j = 0; j < 8; j++) out = out.concat(wordsToBytes(h[j]))
  return out
}

var HASHES = {
  SHA1: { fn: sha1, block: 64 },
  SHA256: { fn: sha256, block: 64 },
  SHA512: { fn: sha512, block: 128 }
}

function hmac(algorithm, key, message) {
  var hash = HASHES[algorithm] || HASHES.SHA1
  var k = key.length > hash.block ? hash.fn(key) : key.slice()
  while (k.length < hash.block) k.push(0)
  var inner = []
  var outer = []
  for (var i = 0; i < hash.block; i++) {
    inner.push(k[i] ^ 0x36)
    outer.push(k[i] ^ 0x5c)
  }
  return hash.fn(outer.concat(hash.fn(inner.concat(message))))
}

function hex(bytes) {
  var out = ""
  for (var i = 0; i < bytes.length; i++) out += (bytes[i] < 16 ? "0" : "") + bytes[i].toString(16)
  return out
}

// ------------------------------------------------------------ codes

// RFC 4226's HOTP: the counter as eight bytes, big-endian, through HMAC, and
// "dynamic truncation" down to a number of `digits` digits.
function hotp(keyBytes, counter, digits, algorithm) {
  var hi = Math.floor(counter / 4294967296)
  var lo = counter % 4294967296
  var msg = [(hi >>> 24) & 255, (hi >>> 16) & 255, (hi >>> 8) & 255, hi & 255,
             (lo >>> 24) & 255, (lo >>> 16) & 255, (lo >>> 8) & 255, lo & 255]
  var h = hmac(algorithm, keyBytes, msg)
  var o = h[h.length - 1] & 15
  var bin = ((h[o] & 0x7f) * 16777216) + (h[o + 1] << 16) + (h[o + 2] << 8) + h[o + 3]
  var code = String(bin % Math.pow(10, digits))
  while (code.length < digits) code = "0" + code
  return code
}

// Which thirty seconds (or `period`) a moment is in.
function counterAt(ms, period) { return Math.floor(ms / 1000 / (period || DEFAULT_PERIOD)) }

// Seconds left in the current period, 1..period.
function remainingAt(ms, period) {
  var p = period || DEFAULT_PERIOD
  return p - Math.floor(ms / 1000) % p
}

// The account's code for a counter, or "" when its secret will not decode.
function codeFor(account, counter) {
  if (!account) return ""
  var key = base32Decode(account.secret)
  if (!key || !key.length) return ""
  return hotp(key, counter, account.digits || 6, account.algorithm || "SHA1")
}

function codeAt(account, ms) { return codeFor(account, counterAt(ms, account ? account.period : DEFAULT_PERIOD)) }

// "123 456", "1234 5678": two halves, the way a person reads them out.
function grouped(code) {
  var s = String(code || "")
  if (s.length < 6) return s
  var cut = Math.ceil(s.length / 2)
  return s.slice(0, cut) + " " + s.slice(cut)
}

// ------------------------------------------------------------ accounts

function newId(seed) {
  return "a" + Math.floor(seed || Date.now()).toString(36) + Math.floor(Math.random() * 1679616).toString(36)
}

function text(value, max) {
  return typeof value === "string" ? value.trim().slice(0, max || 200) : ""
}

function normAlgorithm(value) {
  var a = String(value || "SHA1").toUpperCase().replace("-", "")
  return ALGORITHMS.indexOf(a) >= 0 ? a : ""
}

// An account as the file and the screen want it, or null when it has no
// usable key. Anything else out of range falls back to its default.
function normalise(raw, seed) {
  if (!raw || typeof raw !== "object") return null
  var secret = cleanSecret(typeof raw.secret === "string" ? raw.secret : "")
  if (secretProblem(secret) !== "") return null
  var digits = Number(raw.digits)
  var period = Math.floor(Number(raw.period))
  return {
    id: text(raw.id, 64) || newId(seed),
    issuer: text(raw.issuer),
    name: text(raw.name),
    secret: secret,
    algorithm: normAlgorithm(raw.algorithm) || "SHA1",
    digits: DIGITS.indexOf(digits) >= 0 ? digits : 6,
    period: period > 0 && period <= MAX_PERIOD ? period : DEFAULT_PERIOD
  }
}

function copy(a) { return Object.assign({}, a) }

function title(a) { return a ? (a.issuer || a.name || "Untitled") : "" }
function subtitle(a) { return a && a.issuer ? a.name : "" }

function sortKey(a) { return (title(a) + "\n" + (a.issuer ? a.name : "")).toLowerCase() }
function byLabel(x, y) {
  var a = sortKey(x)
  var b = sortKey(y)
  return a < b ? -1 : a > b ? 1 : 0
}

function monogram(a) {
  var t = title(a)
  for (var i = 0; i < t.length; i++) {
    var c = t.charAt(i)
    if (c.toLowerCase() !== c.toUpperCase() || (c >= "0" && c <= "9")) return c.toUpperCase()
  }
  return "#"
}

function hueIndex(key, n) {
  var s = String(key || "").toLowerCase()
  if (!s || n <= 0) return 0
  var h = 0
  for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0
  return Math.abs(h) % n
}

function filtered(accounts, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return accounts
  return accounts.filter(function (a) {
    return (a.issuer + " " + a.name).toLowerCase().indexOf(q) >= 0
  })
}

function find(accounts, id) {
  for (var i = 0; i < accounts.length; i++) if (accounts[i].id === id) return accounts[i]
  return null
}

// The list with `a` in it, replacing one with its id, in label order.
function withAccount(accounts, a) {
  var out = accounts.filter(function (x) { return x.id !== a.id })
  out.push(a)
  out.sort(byLabel)
  return out
}

function without(accounts, id) { return accounts.filter(function (x) { return x.id !== id }) }

// The account already holding this key, if any. The same key twice is the
// same login twice, whatever the labels say.
function sameKey(accounts, secret) {
  var s = cleanSecret(secret)
  for (var i = 0; i < accounts.length; i++) if (accounts[i].secret === s) return accounts[i]
  return null
}

// "SHA1 · 6 digits · every 30 s", or "" for the defaults nobody needs told.
function details(a) {
  if (!a) return ""
  var parts = []
  if (a.algorithm !== "SHA1") parts.push(a.algorithm)
  if (a.digits !== 6) parts.push(a.digits + " digits")
  if (a.period !== DEFAULT_PERIOD) parts.push("every " + a.period + " s")
  return parts.join(" · ")
}

// ------------------------------------------------------------ links

function decode(part, plus) {
  var s = String(part || "")
  if (plus) s = s.replace(/\+/g, " ")
  try { return decodeURIComponent(s) } catch (e) { return s }
}

function query(q) {
  var out = ({})
  var pairs = String(q || "").split("&")
  for (var i = 0; i < pairs.length; i++) {
    if (!pairs[i]) continue
    var eq = pairs[i].indexOf("=")
    var k = (eq < 0 ? pairs[i] : pairs[i].slice(0, eq)).toLowerCase()
    var v = eq < 0 ? "" : pairs[i].slice(eq + 1)
    if (!(k in out)) out[k] = v
  }
  return out
}

// One otpauth:// link: { account } or { error }.
function parseUri(uri, seed) {
  var s = String(uri || "").trim()
  var m = /^otpauth:\/\/([^/?#]*)\/?([^?#]*)\??([^#]*)/i.exec(s)
  if (!m) return { error: "Not an otpauth:// link" }
  var type = m[1].toLowerCase()
  if (type === "hotp") return { error: "Counter-based (HOTP) codes are not supported" }
  if (type !== "totp") return { error: "Not a time-based code" }
  var label = decode(m[2], false)
  var params = query(m[3])
  var colon = label.indexOf(":")
  var labelIssuer = colon >= 0 ? label.slice(0, colon).trim() : ""
  var name = (colon >= 0 ? label.slice(colon + 1) : label).trim()
  var issuer = "issuer" in params ? decode(params.issuer, true).trim() : labelIssuer
  if (!issuer) issuer = labelIssuer
  var secret = decode(params.secret, false)
  var problem = secretProblem(secret)
  if (problem) return { error: problem }
  var algorithm = "algorithm" in params ? normAlgorithm(decode(params.algorithm)) : "SHA1"
  if (!algorithm) return { error: "Unsupported algorithm: " + decode(params.algorithm) }
  var digits = "digits" in params ? Number(params.digits) : 6
  if (DIGITS.indexOf(digits) < 0) return { error: "Unsupported length: " + params.digits + " digits" }
  var period = "period" in params ? Number(params.period) : DEFAULT_PERIOD
  if (!(period > 0 && period <= MAX_PERIOD && Math.floor(period) === period))
    return { error: "Unsupported period: " + params.period }
  return { account: normalise({ issuer: issuer, name: name, secret: secret,
                                algorithm: algorithm, digits: digits, period: period }, seed) }
}

// The account as a link any authenticator reads: what a QR code holds. Only
// the parameters that are not the defaults, which is what scanners expect.
function toUri(a) {
  var label = a.issuer ? encodeURIComponent(a.issuer) + ":" + encodeURIComponent(a.name) : encodeURIComponent(a.name)
  var uri = "otpauth://totp/" + label + "?secret=" + a.secret
  if (a.issuer) uri += "&issuer=" + encodeURIComponent(a.issuer)
  if (a.algorithm !== "SHA1") uri += "&algorithm=" + a.algorithm
  if (a.digits !== 6) uri += "&digits=" + a.digits
  if (a.period !== DEFAULT_PERIOD) uri += "&period=" + a.period
  return uri
}

// ------------------------------------------------------------ Google's export

var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function base64Decode(text) {
  var s = String(text || "").replace(/[\s=]/g, "").replace(/-/g, "+").replace(/_/g, "/")
  var out = []
  var bits = 0
  var value = 0
  for (var i = 0; i < s.length; i++) {
    var v = B64.indexOf(s.charAt(i))
    if (v < 0) return null
    value = ((value << 6) | v) & 0xffffff
    bits += 6
    if (bits >= 8) {
      bits -= 8
      out.push((value >>> bits) & 255)
    }
  }
  return out
}

// A protocol buffer's fields, one level deep: [{ field, wire, value }], where
// a varint is a number and a length-delimited field is its bytes. Null when
// the bytes run out mid-field.
function protoFields(bytes) {
  var out = []
  var i = 0
  function varint() {
    var v = 0
    var mul = 1
    while (i < bytes.length) {
      var b = bytes[i++]
      v += (b & 127) * mul
      mul *= 128
      if (!(b & 128)) return v
    }
    return null
  }
  while (i < bytes.length) {
    var key = varint()
    if (key === null) return null
    var field = Math.floor(key / 8)
    var wire = key % 8
    if (wire === 0) {
      var v = varint()
      if (v === null) return null
      out.push({ field: field, wire: wire, value: v })
    } else if (wire === 2) {
      var len = varint()
      if (len === null || i + len > bytes.length) return null
      out.push({ field: field, wire: wire, value: bytes.slice(i, i + len) })
      i += len
    } else if (wire === 1 || wire === 5) {
      i += wire === 1 ? 8 : 4
      if (i > bytes.length) return null
    } else {
      return null
    }
  }
  return out
}

// Google Authenticator's "Transfer accounts" QR code:
// otpauth-migration://offline?data=<base64 protobuf>. Every time-based
// account in it, and how many were left out (counter-based, MD5).
function parseMigration(uri, seed) {
  var m = /^otpauth-migration:\/\/[^?]*\?(.*)$/i.exec(String(uri || "").trim())
  if (!m) return { error: "Not a Google Authenticator export" }
  var bytes = base64Decode(decode(query(m[1]).data, false))
  var top = bytes ? protoFields(bytes) : null
  if (!top) return { error: "The export link is damaged" }
  var accounts = []
  var skipped = 0
  for (var i = 0; i < top.length; i++) {
    if (top[i].field !== 1 || top[i].wire !== 2) continue
    var p = protoFields(top[i].value)
    if (!p) { skipped++; continue }
    var o = { secret: [], name: "", issuer: "", algorithm: 1, digits: 1, type: 2 }
    for (var j = 0; j < p.length; j++) {
      var f = p[j]
      if (f.field === 1 && f.wire === 2) o.secret = f.value
      else if (f.field === 2 && f.wire === 2) o.name = fromUtf8(f.value)
      else if (f.field === 3 && f.wire === 2) o.issuer = fromUtf8(f.value)
      else if (f.field === 4 && f.wire === 0) o.algorithm = f.value
      else if (f.field === 5 && f.wire === 0) o.digits = f.value
      else if (f.field === 6 && f.wire === 0) o.type = f.value
    }
    // 1 HOTP, 2 TOTP (0, unspecified, is TOTP in practice). 4 is MD5.
    var algorithm = ({ 0: "SHA1", 1: "SHA1", 2: "SHA256", 3: "SHA512" })[o.algorithm]
    if (o.type === 1 || !algorithm) { skipped++; continue }
    // The name carries "Issuer:account" when the issuer field is empty.
    var name = o.name
    var colon = name.indexOf(":")
    if (!o.issuer && colon >= 0) { o.issuer = name.slice(0, colon); name = name.slice(colon + 1) }
    else if (o.issuer && name.indexOf(o.issuer + ":") === 0) name = name.slice(o.issuer.length + 1)
    var a = normalise({ issuer: o.issuer, name: name, secret: base32Encode(o.secret),
                        algorithm: algorithm, digits: o.digits === 2 ? 8 : 6 }, (seed || 0) + i)
    if (a) accounts.push(a)
    else skipped++
  }
  return { accounts: accounts, skipped: skipped }
}

// ------------------------------------------------------------ what was pasted

// Whatever went into the add box -- one link, several, an export, or a bare
// key -- as { kind, accounts, errors }:
//
//   kind "links"  every otpauth:// and otpauth-migration:// link in the text
//   kind "key"    no link, and the whole text is a usable key
//   kind "none"   nothing yet, or nothing usable (errors says why)
function read(textIn, seed) {
  var s = String(textIn || "").trim()
  if (s === "") return { kind: "none", accounts: [], errors: [] }
  var links = s.match(/otpauth(-migration)?:\/\/[^\s"'<>]+/gi)
  if (!links) {
    var problem = secretProblem(s)
    return problem ? { kind: "none", accounts: [], errors: [problem] }
                   : { kind: "key", accounts: [], errors: [] }
  }
  var accounts = []
  var errors = []
  for (var i = 0; i < links.length; i++) {
    if (/^otpauth-migration:/i.test(links[i])) {
      var mig = parseMigration(links[i], (seed || 0) + i * 1000)
      if (mig.error) errors.push(mig.error)
      else {
        accounts = accounts.concat(mig.accounts)
        if (mig.skipped) errors.push(mig.skipped + (mig.skipped === 1 ? " account" : " accounts") + " in the export were not time-based")
      }
    } else {
      var one = parseUri(links[i], (seed || 0) + i)
      if (one.error) errors.push(one.error)
      else accounts.push(one.account)
    }
  }
  return { kind: "links", accounts: accounts, errors: errors }
}
