// The two files: the places somebody chose, and the week behind them.
//
// Both are read as objects, because the kit's JsonFile has already told an
// absent file from a broken one. What is tested here is the other half: a file
// somebody has edited by hand, and the rules about a list of places that the
// screen would otherwise have to know.
import QtQuick
import QtTest
import "../Store.js" as Store

TestCase {
  name: "Store"

  function berlin() {
    return { id: "52.524,13.411", name: "Berlin", admin: "Berlin",
             country: "Germany", lat: 52.524, lon: 13.411 }
  }

  function cairo() {
    return { id: "30.044,31.236", name: "Cairo", admin: "Cairo",
             country: "Egypt", lat: 30.044, lon: 31.236 }
  }

  function state(places, current, units) {
    return { places: places, current: current, units: units || "metric" }
  }

  function roundTrip(s) {
    return Store.parsePlaces(JSON.parse(Store.serializePlaces(s)))
  }

  // --- the places --------------------------------------------------------

  function test_places_go_out_and_come_back() {
    var back = roundTrip(state([berlin(), cairo()], cairo().id, "imperial"))
    compare(back.places.length, 2)
    compare(back.places[1].name, "Cairo")
    compare(back.places[1].lat, 30.044)
    compare(back.current, cairo().id)
    compare(back.units, "imperial")
  }

  function test_nothing_at_all_is_an_empty_list_rather_than_a_failure() {
    compare(Store.parsePlaces(null).places.length, 0)
    compare(Store.parsePlaces(null).current, "")
    compare(Store.parsePlaces({}).units, "metric")
    compare(Store.parsePlaces({ places: "Berlin" }).places.length, 0)
  }

  function test_a_file_somebody_has_edited_cannot_put_anything_but_a_place_on_screen() {
    var data = { places: [
      { id: "1,1", name: 12, lat: 1, lon: 1 },
      { id: "2,2", name: "No latitude" },
      { id: "3,3", name: "Off the globe", lat: 191, lon: 0 },
      { name: "No id", lat: 4, lon: 4 },
      { id: "5,5", name: "  Padded  ", lat: 5, lon: 5 }
    ]}
    var back = Store.parsePlaces(data)
    compare(back.places.length, 1)
    compare(back.places[0].name, "Padded")
  }

  function test_a_scale_this_app_does_not_have_is_the_one_it_does() {
    compare(Store.parsePlaces({ units: "kelvin" }).units, "metric")
    compare(Store.parsePlaces({ units: "IMPERIAL" }).units, "imperial")
  }

  function test_the_same_place_twice_is_one_row() {
    var back = Store.parsePlaces({ places: [berlin(), berlin()] })
    compare(back.places.length, 1)
  }

  function test_a_current_naming_nowhere_falls_back_to_the_first_place() {
    // What removing a place in an editor leaves behind.
    var back = Store.parsePlaces({ places: [berlin(), cairo()], current: "0,0" })
    compare(back.current, berlin().id)
    compare(Store.parsePlaces({ current: "0,0" }).current, "")
  }

  function test_adding_a_place_shows_it() {
    var result = Store.add(state([berlin()], berlin().id), cairo())
    compare(result.added, true)
    compare(result.state.places.length, 2)
    compare(result.state.current, cairo().id)
  }

  function test_adding_a_place_that_is_already_there_shows_it_rather_than_refusing() {
    var result = Store.add(state([berlin(), cairo()], cairo().id), berlin())
    compare(result.added, false)
    compare(result.full, false)
    compare(result.state.places.length, 2)
    compare(result.state.current, berlin().id)
  }

  function test_there_is_a_ceiling_and_it_says_so() {
    var places = []
    for (var i = 0; i < Store.MAX_PLACES; i++)
      places.push({ id: i + ",0", name: "Place " + i, lat: i, lon: 0 })
    var result = Store.add(state(places, places[0].id), cairo())
    compare(result.full, true)
    compare(result.state.places.length, Store.MAX_PLACES)
  }

  function test_a_file_longer_than_the_ceiling_is_read_up_to_it() {
    var places = []
    for (var i = 0; i < Store.MAX_PLACES + 5; i++)
      places.push({ id: i + ",0", name: "Place " + i, lat: i, lon: 0 })
    compare(Store.parsePlaces({ places: places }).places.length, Store.MAX_PLACES)
  }

  function test_removing_the_place_on_screen_moves_to_its_neighbour() {
    var oslo = { id: "59.913,10.739", name: "Oslo", lat: 59.913, lon: 10.739 }
    var next = Store.remove(state([berlin(), cairo(), oslo], cairo().id), cairo().id)
    compare(next.places.length, 2)
    // The row that was under the thumb, not the top of the list.
    compare(next.current, oslo.id)
  }

  function test_removing_the_last_place_leaves_nowhere() {
    var next = Store.remove(state([berlin()], berlin().id), berlin().id)
    compare(next.places.length, 0)
    compare(next.current, "")
  }

  function test_removing_a_place_that_is_not_shown_does_not_move_the_screen() {
    var next = Store.remove(state([berlin(), cairo()], berlin().id), cairo().id)
    compare(next.current, berlin().id)
  }

  function test_choosing_a_place_that_is_not_on_the_list_changes_nothing() {
    var next = Store.select(state([berlin()], berlin().id), "0,0")
    compare(next.current, berlin().id)
  }

  // --- the cache ---------------------------------------------------------

  function forecast() {
    return {
      offset: 7200,
      current: { time: 1789567200, temp: 18.4, feels: 17.1, humidity: 62,
                 precip: 0, code: 2, wind: 12.6, from: 315, day: true },
      hourly: [{ time: 1789567200, temp: 18.4, code: 2, pop: 10, day: true }],
      daily: [{ time: 1789531200, code: 2, high: 21, low: 9, pop: 20,
                sunrise: 1789533660, sunset: 1789580320 }]
    }
  }

  function test_a_forecast_goes_out_and_comes_back() {
    var entries = Store.put({}, berlin().id, forecast(), 1789567300)
    var back = Store.parseCache(JSON.parse(Store.serializeCache(entries, [berlin()])))
    compare(back[berlin().id].fetched, 1789567300)
    compare(back[berlin().id].forecast.current.temp, 18.4)
    compare(back[berlin().id].forecast.daily[0].high, 21)
    compare(back[berlin().id].forecast.offset, 7200)
  }

  function test_a_place_that_is_gone_does_not_leave_its_week_behind() {
    var entries = Store.put({}, berlin().id, forecast(), 1)
    entries = Store.put(entries, cairo().id, forecast(), 1)
    var written = JSON.parse(Store.serializeCache(entries, [cairo()]))
    compare(written.forecasts[berlin().id], undefined)
    verify(!!written.forecasts[cairo().id])
  }

  function test_a_cache_that_is_not_one_is_empty_rather_than_fatal() {
    compare(Object.keys(Store.parseCache(null)).length, 0)
    compare(Object.keys(Store.parseCache({ forecasts: 12 })).length, 0)
    compare(Object.keys(Store.parseCache({ forecasts: { "1,1": {} } })).length, 0)
  }

  function test_a_forecast_off_the_disk_is_read_as_strictly_as_one_off_the_wire() {
    var broken = {
      offset: "two hours",
      current: { time: 1789567200, temp: "warm" },
      hourly: [{ time: 1789567200, temp: 18.4, code: 2, pop: null, day: true },
               { time: 1789570800, temp: null, code: 2 }],
      daily: [{ time: 1789531200, high: 21 }]
    }
    var back = Store.parseCache({ forecasts: { "1,1": { fetched: 5, forecast: broken } } })
    var kept = back["1,1"].forecast
    // A temperature that is a word is not a temperature, and a day with no low
    // cannot be drawn as a bar.
    compare(kept.current, null)
    compare(kept.hourly.length, 1)
    compare(kept.daily.length, 0)
    compare(kept.offset, 0)
  }

  function test_a_forecast_with_nothing_readable_in_it_is_not_kept_at_all() {
    var back = Store.parseCache({ forecasts: {
      "1,1": { fetched: 5, forecast: { offset: 0, hourly: [], daily: [] } }
    }})
    compare(Object.keys(back).length, 0)
  }
}
