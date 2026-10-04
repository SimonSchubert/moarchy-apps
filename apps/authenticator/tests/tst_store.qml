// accounts.json: what is read, what is kept aside and written back as it
// was, and the shape the file goes out in. The file is the backup, so its
// shape is a promise, not a detail.
import QtQuick
import QtTest
import "../Store.js" as Store

TestCase {
  name: "AuthenticatorStore"

  function test_nothing_or_nonsense_is_an_empty_list() {
    compare(Store.parse(null).accounts, [])
    compare(Store.parse("x").accounts, [])
    compare(Store.parse({ accounts: "all of them" }).accounts, [])
    compare(Store.parse({}).strays, [])
  }

  function test_a_row_without_a_key_is_written_back_untouched() {
    var odd = { id: "x1", issuer: "Bank", secret: "not base32!" }
    var state = Store.parse({ schema: 1, accounts: [{ id: "a", issuer: "A", secret: "JBSWY3DPEHPK3PXP" }, odd, 42] })
    compare(state.accounts.length, 1)
    compare(state.strays.length, 2)
    var out = JSON.parse(Store.serialize(state.accounts, state.strays))
    compare(out.accounts.length, 3)
    compare(out.accounts[1], odd)
    compare(out.accounts[2], 42)
  }

  function test_every_field_is_written_defaults_and_all() {
    var state = Store.parse({ accounts: [{ id: "a", issuer: " A ", name: "me", secret: "jbsw y3dp ehpk 3pxp" }] })
    var row = JSON.parse(Store.serialize(state.accounts, [])).accounts[0]
    compare(row, { id: "a", issuer: "A", name: "me", secret: "JBSWY3DPEHPK3PXP", algorithm: "SHA1", digits: 6, period: 30 })
  }

  function test_out_of_range_settings_fall_back() {
    var a = Store.parse({ accounts: [{ secret: "JBSWY3DPEHPK3PXP", algorithm: "MD5", digits: 9, period: -4 }] }).accounts[0]
    compare(a.algorithm, "SHA1")
    compare(a.digits, 6)
    compare(a.period, 30)
    verify(a.id.length > 0)
  }

  function test_a_repeated_id_is_given_a_new_one() {
    var state = Store.parse({ accounts: [{ id: "same", issuer: "A", secret: "JBSWY3DPEHPK3PXP" },
                                         { id: "same", issuer: "B", secret: "GEZDGNBVGY3TQOJQ" }] })
    compare(state.accounts.length, 2)
    verify(state.accounts[0].id !== state.accounts[1].id)
  }

  function test_the_file_has_a_schema_and_a_list_in_label_order() {
    var state = Store.parse({ accounts: [{ id: "z", issuer: "Zulip", secret: "JBSWY3DPEHPK3PXP" },
                                         { id: "a", issuer: "aur", secret: "GEZDGNBVGY3TQOJQ" }] })
    var out = JSON.parse(Store.serialize(state.accounts, []))
    compare(out.schema, 1)
    compare(out.accounts[0].id, "a")
  }
}
