// The codes, against RFC 6238's own table; and everything between a QR code
// and an account. A code wrong in one digit is a login refused with no hint
// why, so the hashes are checked here and not trusted.
import QtQuick
import QtTest
import "../Otp.js" as Otp

TestCase {
  name: "Otp"

  function ascii(s) { return Otp.utf8(s) }

  function test_the_hashes_of_abc() {
    compare(Otp.hex(Otp.sha1(ascii("abc"))), "a9993e364706816aba3e25717850c26c9cd0d89d")
    compare(Otp.hex(Otp.sha256(ascii("abc"))), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    compare(Otp.hex(Otp.sha512(ascii("abc"))),
            "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
            + "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
  }

  // Two blocks, so the padding and the carry between blocks are both used.
  function test_the_hashes_of_a_long_message() {
    var m = ascii("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
    compare(Otp.hex(Otp.sha1(m)), "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
    compare(Otp.hex(Otp.sha256(m)), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    compare(Otp.hex(Otp.sha512(ascii(""))),
            "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce"
            + "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")
  }

  // RFC 2202 / 4231, case 2: a key shorter than the block.
  function test_hmac() {
    compare(Otp.hex(Otp.hmac("SHA1", ascii("Jefe"), ascii("what do ya want for nothing?"))),
            "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79")
    compare(Otp.hex(Otp.hmac("SHA256", ascii("Jefe"), ascii("what do ya want for nothing?"))),
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
  }

  // RFC 6238, appendix B: every time, every algorithm, eight digits.
  function test_rfc_6238() {
    var k1 = ascii("12345678901234567890")
    var k2 = ascii("12345678901234567890123456789012")
    var k3 = ascii("1234567890123456789012345678901234567890123456789012345678901234")
    var table = [
      [59, "94287082", "46119246", "90693936"],
      [1111111109, "07081804", "68084774", "25091201"],
      [1111111111, "14050471", "67062674", "99943326"],
      [1234567890, "89005924", "91819424", "93441116"],
      [2000000000, "69279037", "90698825", "38618901"],
      [20000000000, "65353130", "77737706", "47863826"]
    ]
    for (var i = 0; i < table.length; i++) {
      var c = Math.floor(table[i][0] / 30)
      compare(Otp.hotp(k1, c, 8, "SHA1"), table[i][1], "SHA1 at " + table[i][0])
      compare(Otp.hotp(k2, c, 8, "SHA256"), table[i][2], "SHA256 at " + table[i][0])
      compare(Otp.hotp(k3, c, 8, "SHA512"), table[i][3], "SHA512 at " + table[i][0])
    }
  }

  // RFC 4226, appendix D: six digits from the same key, a counter at a time.
  function test_rfc_4226() {
    var want = ["755224", "287082", "359152", "969429", "338314", "254676", "287922", "162583", "399871", "520489"]
    for (var i = 0; i < want.length; i++) compare(Otp.hotp(ascii("12345678901234567890"), i, 6, "SHA1"), want[i])
  }

  function test_an_account_from_its_base32_key() {
    var a = Otp.normalise({ secret: "gezd gnbv gy3t qojq gezd gnbv gy3t qojq", issuer: "X" }, 1)
    compare(a.secret, "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
    compare(Otp.codeAt(a, 59000), "287082")
    compare(Otp.grouped("287082"), "287 082")
    compare(Otp.grouped("94287082"), "9428 7082")
  }

  function test_base32_round_trip_and_rejects() {
    compare(Otp.base32Encode(Otp.base32Decode("JBSWY3DPEHPK3PXP")), "JBSWY3DPEHPK3PXP")
    compare(Otp.base32Decode("JBSW-Y3DP=="), [72, 101, 108, 108, 111])
    compare(Otp.base32Decode("NOT1VALID"), null)
    compare(Otp.secretProblem(""), "No key")
    verify(Otp.secretProblem("abc") !== "")
    verify(Otp.secretProblem("0OO0OOOO") !== "")
    compare(Otp.secretProblem("JBSWY3DPEHPK3PXP"), "")
    compare(Otp.normalise({ secret: "hello" }, 1), null)
  }

  function test_the_period_and_what_is_left_of_it() {
    compare(Otp.remainingAt(0, 30), 30)
    compare(Otp.remainingAt(29999, 30), 1)
    compare(Otp.remainingAt(30000, 30), 30)
    compare(Otp.counterAt(59000, 30), 1)
    compare(Otp.counterAt(59000, 60), 0)
  }

  function test_the_link_googles_wiki_gives() {
    var r = Otp.parseUri("otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example", 1)
    compare(r.account.issuer, "Example")
    compare(r.account.name, "alice@google.com")
    compare(r.account.secret, "JBSWY3DPEHPK3PXP")
    compare(r.account.algorithm, "SHA1")
    compare(r.account.digits, 6)
    compare(r.account.period, 30)
  }

  function test_a_link_with_everything_spelled_out() {
    var r = Otp.parseUri("otpauth://totp/ACME%20Co:john.doe%40email.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=ACME+Co&algorithm=sha256&digits=8&period=60", 1)
    compare(r.account.issuer, "ACME Co")
    compare(r.account.name, "john.doe@email.com")
    compare(r.account.algorithm, "SHA256")
    compare(r.account.digits, 8)
    compare(r.account.period, 60)
    compare(Otp.details(r.account), "SHA256 · 8 digits · every 60 s")
  }

  function test_the_issuer_parameter_wins_and_the_label_fills_in() {
    compare(Otp.parseUri("otpauth://totp/Old:me?secret=JBSWY3DPEHPK3PXP&issuer=New", 1).account.issuer, "New")
    compare(Otp.parseUri("otpauth://totp/Old:me?secret=JBSWY3DPEHPK3PXP", 1).account.issuer, "Old")
    var bare = Otp.parseUri("otpauth://totp/me?secret=JBSWY3DPEHPK3PXP", 1).account
    compare(bare.issuer, "")
    compare(Otp.title(bare), "me")
  }

  function test_links_that_will_not_do() {
    verify(Otp.parseUri("otpauth://hotp/X?secret=JBSWY3DPEHPK3PXP&counter=1").error.indexOf("HOTP") >= 0)
    verify(Otp.parseUri("otpauth://totp/X?issuer=X").error !== undefined)
    verify(Otp.parseUri("otpauth://totp/X?secret=JBSWY3DPEHPK3PXP&algorithm=MD5").error !== undefined)
    verify(Otp.parseUri("otpauth://totp/X?secret=JBSWY3DPEHPK3PXP&digits=4").error !== undefined)
    verify(Otp.parseUri("otpauth://totp/X?secret=JBSWY3DPEHPK3PXP&period=0").error !== undefined)
    verify(Otp.parseUri("https://example.com").error !== undefined)
  }

  function test_a_link_goes_out_as_it_came_in() {
    var a = Otp.normalise({ issuer: "ACME Co", name: "john@x.org", secret: "JBSWY3DPEHPK3PXP", digits: 8 }, 1)
    var uri = Otp.toUri(a)
    compare(uri, "otpauth://totp/ACME%20Co:john%40x.org?secret=JBSWY3DPEHPK3PXP&issuer=ACME%20Co&digits=8")
    var back = Otp.parseUri(uri, 2).account
    compare(back.issuer, a.issuer)
    compare(back.name, a.name)
    compare(back.digits, 8)
  }

  // Built by hand in Python from Google's proto: two TOTP accounts, one of
  // them SHA256 with eight digits and its issuer only in the name, and a
  // counter-based one that has to be left out.
  readonly property string googleExport: "otpauth-migration://offline?data=Ci4KCkhlbGxvId6tvu8SEWFsaWNlQGV4YW1wbGUuY29tGgdFeGFtcGxlIAEoATACCisKFDEyMzQ1Njc4OTAxMjM0NTY3ODkwEgtCw7xjaGVyOmJvYhoAIAIoAjACCioKFDEyMzQ1Njc4OTAxMjM0NTY3ODkwEgdjb3VudGVyGgNPbGQgASgBMAEQARgBIAA%3D"

  function test_google_authenticators_export() {
    var r = Otp.parseMigration(googleExport, 1)
    compare(r.accounts.length, 2)
    compare(r.skipped, 1)
    compare(r.accounts[0].issuer, "Example")
    compare(r.accounts[0].name, "alice@example.com")
    compare(r.accounts[0].secret, "JBSWY3DPEHPK3PXP")
    compare(r.accounts[1].issuer, "B" + String.fromCharCode(0xfc) + "cher")
    compare(r.accounts[1].name, "bob")
    compare(r.accounts[1].algorithm, "SHA256")
    compare(r.accounts[1].digits, 8)
    compare(r.accounts[1].secret, "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
  }

  function test_what_was_pasted() {
    compare(Otp.read("", 1).kind, "none")
    compare(Otp.read("jbsw y3dp ehpk 3pxp", 1).kind, "key")
    var bad = Otp.read("not a key", 1)
    compare(bad.kind, "none")
    compare(bad.errors.length, 1)
    var two = Otp.read("otpauth://totp/A:a?secret=JBSWY3DPEHPK3PXP\n  otpauth://totp/B:b?secret=GEZDGNBVGY3TQOJQ\n", 1)
    compare(two.kind, "links")
    compare(two.accounts.length, 2)
    compare(two.accounts[1].issuer, "B")
    var mixed = Otp.read(googleExport + " otpauth://hotp/X?secret=JBSWY3DPEHPK3PXP", 1)
    compare(mixed.accounts.length, 2)
    compare(mixed.errors.length, 2)
  }

  function test_the_list() {
    var a = Otp.normalise({ id: "a", issuer: "github", name: "me", secret: "JBSWY3DPEHPK3PXP" }, 1)
    var b = Otp.normalise({ id: "b", issuer: "Codeberg", name: "me", secret: "GEZDGNBVGY3TQOJQ" }, 1)
    var list = Otp.withAccount(Otp.withAccount([], a), b)
    compare(list[0].id, "b")
    compare(Otp.filtered(list, "GIT").length, 1)
    compare(Otp.sameKey(list, "jbsw y3dp ehpk 3pxp").id, "a")
    compare(Otp.without(list, "a").length, 1)
    compare(Otp.monogram(a), "G")
    compare(Otp.monogram({ issuer: "", name: "" }), "U")
    compare(Otp.monogram({ issuer: "--", name: "" }), "#")
    compare(Otp.hueIndex("github", 7), Otp.hueIndex("GitHub", 7))
  }
}
