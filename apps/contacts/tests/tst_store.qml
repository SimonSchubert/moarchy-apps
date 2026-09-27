// contacts.json: what is read, what is kept aside and written back as it was,
// and the shape the file goes out in. Mail reads the same file, so its shape
// is the contract, not a detail.
import QtQuick
import QtTest
import "../Contacts.js" as Contacts
import "../Store.js" as Store

TestCase {
  name: "ContactsStore"

  function test_nothing_or_nonsense_is_an_empty_book() {
    compare(Store.parse(null).contacts, [])
    compare(Store.parse("x").contacts, [])
    compare(Store.parse({ contacts: "all of them" }).contacts, [])
    compare(Store.parse({}).strays, [])
  }

  function test_a_row_that_cannot_be_drawn_is_written_back_untouched() {
    var odd = { id: "x1", birthday: "1815-12-10" }
    var state = Store.parse({ schema: 1, contacts: [{ id: "a", name: "Ada" }, odd, 42] })
    compare(state.contacts.length, 1)
    compare(state.strays.length, 2)
    var out = JSON.parse(Store.serialize(state.contacts, state.strays))
    compare(out.contacts.length, 3)
    compare(out.contacts[1], odd)
    compare(out.contacts[2], 42)
  }

  function test_a_repeated_id_is_given_a_new_one() {
    var state = Store.parse({ contacts: [{ id: "same", name: "A" }, { id: "same", name: "B" }] })
    compare(state.contacts.length, 2)
    verify(state.contacts[0].id !== state.contacts[1].id)
  }

  function test_a_row_with_no_id_gets_one() {
    var state = Store.parse({ contacts: [{ name: "Nameless id" }] })
    verify(state.contacts[0].id.length > 0)
  }

  function test_fields_are_trimmed_and_non_strings_dropped() {
    var c = Store.parse({ contacts: [{ id: "a", name: "  Ada ", phone: 12345, email: " a@b.c " }] }).contacts[0]
    compare(c.name, "Ada")
    compare(c.phone, "")
    compare(c.email, "a@b.c")
  }

  function test_the_file_has_a_schema_and_a_list() {
    var out = JSON.parse(Store.serialize([], []))
    compare(out.schema, 1)
    compare(out.contacts, [])
  }

  function test_a_contact_with_only_a_number_is_filed_by_it() {
    var c = { id: "n", name: "", phone: "0152 555", email: "", note: "" }
    compare(Contacts.initial(c), "#")
    compare(Contacts.line(c), "0152 555")
    compare(Contacts.monogram(c), "0")
  }

  function test_the_monogram_is_first_and_last_initials() {
    compare(Contacts.monogram({ name: "Ada Okonkwo" }), "AO")
    compare(Contacts.monogram({ name: "Mum" }), "M")
    compare(Contacts.monogram({ name: "Anna Maria van Dijk" }), "AD")
  }

  function test_a_person_keeps_one_colour() {
    var a = Contacts.hueIndex("ada okonkwo", 7)
    compare(Contacts.hueIndex("ada okonkwo", 7), a)
    verify(a >= 0 && a < 7)
    compare(Contacts.hueIndex("", 7), 0)
  }

  function test_saving_an_edit_replaces_the_person_in_name_order() {
    var list = [{ id: "a", name: "Bea", phone: "", email: "", note: "" },
                { id: "b", name: "Cal", phone: "", email: "", note: "" }]
    var out = Contacts.withContact(list, { id: "b", name: "Abe", phone: "1", email: "", note: "" })
    compare(out.length, 2)
    compare(out[0].id, "b")
    compare(out[0].phone, "1")
    compare(Contacts.without(out, "b").length, 1)
  }
}
