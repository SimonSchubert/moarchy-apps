// Somebody else's JSON, our own barcodes, and every number on screen, against
// the cases 0.1.0's test_facts.py had. Nothing here opens a socket: a fetch is
// what curl printed, handed to Facts.answer().
import QtQuick
import QtTest
import "../Facts.js" as F

TestCase {
  name: "FoodFacts"

  readonly property string nutella: "3017620422003"

  function record() {
    return {
      status: 1,
      code: nutella,
      product: {
        code: nutella,
        product_name: "Nutella",
        product_name_en: "Nutella",
        brands: "Ferrero, Nutella",
        quantity: "400 g",
        nutriscore_grade: "e",
        nova_group: 4,
        ecoscore_grade: "d",
        allergens_tags: ["en:milk", "en:nuts", "en:soybeans"],
        ingredients_text_en: "Sugar, palm oil, hazelnuts.",
        nutriments: {
          "energy-kcal_100g": 539, fat_100g: 30.9, "saturated-fat_100g": 10.6,
          carbohydrates_100g: 57.5, sugars_100g: 56.3, fiber_100g: 0,
          proteins_100g: 6.3, salt_100g: 0.107
        },
        image_front_small_url: "https://images.openfoodfacts.org/front.jpg",
        additives_n: 2
      }
    }
  }

  // --- parsing -----------------------------------------------------------

  function test_a_product_comes_through_whole() {
    var p = F.parse(record()).product
    compare(p.code, nutella)
    compare(p.name, "Nutella")
    compare(p.brand, "Ferrero")
    compare(p.nutriscore, "e")
    compare(p.nova, 4)
    compare(p.allergens, ["Milk", "Nuts", "Soybeans"])
    compare(p.nutrients.length, 8)
    compare(F.drawn(p.nutrients[0]), "539 kcal")
    compare(F.drawn(p.nutrients[1]), "30.9 g")
    compare(p.additives, 2)
    compare(F.subtitle(p), "Ferrero · 400 g")
  }

  function test_english_name_wins() {
    var p = F.parse({ status: 1, product: { code: nutella, product_name: "Pâte à tartiner", product_name_en: "Nutella" } }).product
    compare(p.name, "Nutella")
  }

  function test_a_missing_product_is_missing_not_malformed() {
    var r = F.parse({ status: 0, code: nutella, status_verbose: "product not found" })
    verify(r.error.missing)
    verify(r.error.message.indexOf(nutella) >= 0)
  }

  function test_a_product_with_no_name_is_not_a_page() {
    var r = F.parse({ status: 1, product: { code: nutella } })
    verify(r.error)
    verify(!r.error.missing)
  }

  function test_unknown_grades_are_blank_not_a_letter() {
    var p = F.parse({ status: 1, product: { code: nutella, product_name: "Water",
      nutriscore_grade: "not-applicable", ecoscore_grade: "unknown", nova_group: 99 } }).product
    compare(p.nutriscore, "")
    compare(p.ecoscore, "")
    compare(p.nova, null)
    compare(F.novaLabel(p), F.DASH)
  }

  function test_round_trip_through_our_own_file() {
    var original = F.parse(record()).product
    var again = F.fromDict(JSON.parse(JSON.stringify(F.toDict(original))))
    compare(again.code, original.code)
    compare(again.allergens, original.allergens)
    compare(again.nutrients[1].value, original.nutrients[1].value)
    compare(again.nova, 4)
  }

  function test_our_own_file_refuses_a_row_with_no_name() {
    compare(F.fromDict({ code: nutella }), null)
    compare(F.fromDict("Nutella"), null)
  }

  function test_the_table_draws_like_0_1_0() {
    compare(F.drawn({ value: 0, unit: "g" }), "0 g")
    compare(F.drawn({ value: 0.107, unit: "g" }), "0.11 g")
    compare(F.drawn({ value: 3.02, unit: "g" }), "3 g")
    compare(F.drawn({ value: 42, unit: "kcal" }), "42 kcal")
    compare(F.drawn({ value: 10.6, unit: "g" }), "10.6 g")
  }

  function test_nova_is_a_word_as_well_as_a_number() {
    compare(F.novaLabel({ nova: 1 }), "Unprocessed")
    compare(F.novaLabel({ nova: 4 }), "Ultra-processed")
  }

  // --- barcodes ----------------------------------------------------------

  function test_nutella_is_an_ean13() { compare(F.normalize(nutella), nutella) }

  function test_a_upc_a_is_padded_to_ean13() {
    compare(F.normalize("036000291452"), "0036000291452")
  }

  function test_a_wrong_checksum_is_not_sent() { compare(F.normalize("3017620422004"), null) }

  function test_letters_are_not_a_barcode() {
    compare(F.normalize("hello"), null)
    compare(F.normalize(""), null)
  }

  function test_an_ean8_is_itself() { compare(F.normalize("96385074"), "96385074") }

  function test_an_ean13_scan_is_accepted() { compare(F.fromScan("EAN-13", nutella), nutella) }

  function test_zbar_spells_kinds_without_the_dash_too() { compare(F.fromScan("EAN13", nutella), nutella) }

  function test_a_qr_code_is_not_a_product() {
    compare(F.fromScan("QR-Code", nutella), null)
    compare(F.fromScan("QRCode", "https://example.com"), null)
  }

  function test_a_bare_digit_string_is_allowed() { compare(F.fromScan("", nutella), nutella) }

  // --- the wire ----------------------------------------------------------

  function test_a_product_url_names_the_barcode_and_the_app() {
    var argv = F.command(nutella)
    verify(argv[argv.length - 1].indexOf(nutella) >= 0)
    verify(argv.indexOf("User-Agent: " + F.AGENT) >= 0)
    verify(F.AGENT.indexOf("moarchy-food") === 0)
    verify(argv.indexOf("--max-filesize") >= 0)
  }

  function test_an_answer_is_a_product() {
    var r = F.answer(0, JSON.stringify(record()) + "\n200", "", nutella)
    compare(r.product.name, "Nutella")
  }

  function test_a_429_is_ordinary() {
    var r = F.answer(0, "slow down\n429", "HTTP/2 429\r\nretry-after: 30\r\n", nutella)
    compare(r.error.retry, 30)
    verify(!r.error.missing)
    compare(F.answer(0, "\n429", "", nutella).error.retry, F.RATE_LIMIT_S)
  }

  function test_a_404_is_missing() {
    verify(F.answer(0, "{}\n404", "", nutella).error.missing)
  }

  function test_a_server_in_trouble_and_no_network_are_sentences() {
    compare(F.answer(0, "\n503", "", nutella).error.message, "Open Food Facts is having trouble.")
    compare(F.answer(6, "", "", nutella).error.message, "No answer from Open Food Facts.")
    compare(F.answer(63, "", "", nutella).error.message, "Open Food Facts sent more than this app will read.")
    compare(F.answer(0, "<html>\n200", "", nutella).error.message, "Open Food Facts sent something that is not JSON.")
  }

  function test_only_an_http_url_is_an_image() {
    verify(F.httpImage("https://images.openfoodfacts.org/x.jpg"))
    verify(!F.httpImage("file:///etc/passwd"))
    verify(!F.httpImage(""))
  }

  function test_freshness_reads_like_0_1_0() {
    compare(F.freshness(10), "just now")
    compare(F.freshness(120), "2 min ago")
    compare(F.freshness(3600), "1 hour ago")
    compare(F.freshness(7300), "2 hours ago")
    compare(F.freshness(86400), "yesterday")
    compare(F.freshness(86400 * 3), "3 days ago")
  }
}
