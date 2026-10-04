// One file, and the rows in it this app cannot read.
//
// `~/.local/share/moarchy-authenticator/accounts.json` is a list of accounts
// with a schema number on it, in label order, legible to a person with a text
// editor and to `jq` -- which is also the whole of the export:
//
//   jq -r '.accounts[] | "otpauth://totp/\(.issuer):\(.name)?secret=\(.secret)"'
//
// A row this app cannot draw (no key, a key that is not base32) is kept as it
// was found and written back untouched, as Contacts does: the next save must
// not be how somebody loses a login.
.pragma library
.import "Otp.js" as Otp

var SCHEMA = 1

function parse(data) {
  var out = { accounts: [], strays: [] }
  if (!data || typeof data !== "object") return out
  var rows = data.accounts
  if (!rows || rows.constructor !== Array) return out

  var seen = {}
  for (var i = 0; i < rows.length; i++) {
    var a = Otp.normalise(rows[i], i + 1)
    if (a === null) { out.strays.push(rows[i]); continue }
    if (seen[a.id]) a.id = Otp.newId(i + 1)
    seen[a.id] = true
    out.accounts.push(a)
  }
  out.accounts.sort(Otp.byLabel)
  return out
}

// Every field, defaults included: a file somebody reads to move their logins
// elsewhere should not need to know what the defaults are.
function toJson(a) {
  return { id: a.id, issuer: a.issuer, name: a.name, secret: a.secret,
           algorithm: a.algorithm, digits: a.digits, period: a.period }
}

function serialize(accounts, strays) {
  var rows = []
  var list = (accounts || []).slice()
  list.sort(Otp.byLabel)
  for (var i = 0; i < list.length; i++) rows.push(toJson(list[i]))
  for (var j = 0; j < (strays || []).length; j++) rows.push(strays[j])
  return JSON.stringify({ schema: SCHEMA, accounts: rows }, null, 1)
}
