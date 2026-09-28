.pragma library

// REST Countries v5, as it answers /countries/v5?limit=100: Canada as the
// demo key returns it (the leaders, translations and palette taken out for
// length), Bolivia with its two capitals and the primary one second, Bouvet
// Island -- a territory with nobody on it -- and five records that are wrong
// in the ways a record can be.
var PAGE = {
 "data": {
  "objects": [
   {
    "names": {
     "alternates": [],
     "common": "Canada",
     "native": {
      "eng": {
       "common": "Canada",
       "official": "Canada"
      },
      "fra": {
       "common": "Canada",
       "official": "Canada"
      }
     },
     "official": "Canada"
    },
    "codes": {
     "alpha_2": "CA",
     "alpha_3": "CAN",
     "ccn3": "124",
     "cioc": "CAN",
     "fifa": "CAN",
     "fips": "CA",
     "gec": "CA"
    },
    "capitals": [
     {
      "attributes": {
       "administrative": false,
       "constitutional": false,
       "executive": false,
       "judicial": false,
       "legislative": false,
       "primary": true
      },
      "coordinates": {
       "lat": 45.42,
       "lng": -75.7
      },
      "name": "Ottawa"
     }
    ],
    "flag": {
     "colors": {
      "dominant": "#fcfaf5",
      "prominent": "#ff181b"
     },
     "description": "The flag of Canada is composed of a red vertical band on the hoist and fly sides and a central white square that is twice the width of the vertical bands. A large eleven-pointed red maple leaf is centered in the white square.",
     "emoji": "🇨🇦",
     "html_entity": "&#127464;&#127462;",
     "unicode": "U+1F1E8 U+1F1E6",
     "url_png": "https://flags.restcountries.com/v5/w640/ca.png",
     "url_svg": "https://flags.restcountries.com/v5/svg/ca.svg"
    },
    "region": "Americas",
    "subregion": "North America",
    "area": {
     "kilometers": 9984670,
     "miles": 3855101.1
    },
    "borders": [
     "USA"
    ],
    "calling_codes": [
     "1"
    ],
    "cars": {
     "driving_side": "right",
     "signs": [
      "CDN"
     ]
    },
    "classification": {
     "dependency": false,
     "dependency_type": "",
     "disputed": false,
     "iso_status": "official",
     "sovereign": true,
     "un_member": true,
     "un_observer": false
    },
    "continents": [
     "North America"
    ],
    "coordinates": {
     "lat": 60,
     "lng": -95
    },
    "currencies": [
     {
      "code": "CAD",
      "name": "Canadian dollar",
      "symbol": "$"
     }
    ],
    "date": {
     "academic_year_start": {
      "day": 1,
      "month": 9
     },
     "fiscal_year_start": {
      "corporate": {
       "basis": "convention",
       "day": 1,
       "month": 1
      },
      "government": {
       "day": 1,
       "month": 4
      },
      "personal": {
       "day": 1,
       "month": 1
      }
     },
     "start_of_week": "sunday"
    },
    "demonyms": {
     "eng": {
      "f": "Canadian",
      "m": "Canadian"
     },
     "fra": {
      "f": "Canadienne",
      "m": "Canadien"
     }
    },
    "descriptions": {
     "long": "Canada is a Commonwealth realm with Ottawa as its capital and English and French as official languages. The Canadian dollar is the currency, and energy, minerals, forestry, manufacturing and services support a mostly southern population.",
     "short": "Canada is a federal parliamentary state in northern North America, second in the world by area."
    },
    "government_type": "Federal parliamentary constitutional monarchy",
    "landlocked": false,
    "languages": [
     {
      "bcp47": "en",
      "iso639_1": "en",
      "iso639_2b": "eng",
      "iso639_2t": "eng",
      "iso639_3": "eng",
      "name": "English",
      "native_name": "English"
     },
     {
      "bcp47": "fr",
      "iso639_1": "fr",
      "iso639_2b": "fre",
      "iso639_2t": "fra",
      "iso639_3": "fra",
      "name": "French",
      "native_name": "français"
     }
    ],
    "memberships": {
     "african_union": false,
     "arab_league": false,
     "asean": false,
     "brics": false,
     "commonwealth": true,
     "eu": false,
     "eurozone": false,
     "g20": true,
     "g7": true,
     "nato": true,
     "oecd": true,
     "opec": false,
     "schengen": false,
     "un": true
    },
    "population": 41798407,
    "timezones": [
     "UTC-08:00",
     "UTC-07:00",
     "UTC-06:00",
     "UTC-05:00",
     "UTC-04:00",
     "UTC-03:30"
    ],
    "tlds": [
     ".ca"
    ]
   },
   {
    "names": {
     "common": "Bolivia",
     "official": "Plurinational State of Bolivia",
     "native": {
      "aym": {
       "common": "Wuliwya",
       "official": "Wuliwya Suyu"
      },
      "spa": {
       "common": "Bolivia",
       "official": "Estado Plurinacional de Bolivia"
      }
     }
    },
    "codes": {
     "alpha_2": "bo",
     "alpha_3": "BOL"
    },
    "capitals": [
     {
      "name": "La Paz",
      "attributes": {
       "primary": false
      },
      "coordinates": {
       "lat": -16.5,
       "lng": -68.15
      }
     },
     {
      "name": "Sucre",
      "attributes": {
       "primary": true
      },
      "coordinates": {
       "lat": -19.02,
       "lng": -65.26
      }
     }
    ],
    "region": "Americas",
    "subregion": "South America",
    "population": 12332252,
    "area": {
     "kilometers": 1098581
    },
    "languages": [
     {
      "name": "Aymara"
     },
     {
      "name": "Guaraní"
     },
     {
      "name": "Quechua"
     },
     {
      "name": "Spanish"
     }
    ],
    "currencies": [
     {
      "code": "BOB",
      "name": "Bolivian boliviano",
      "symbol": "Bs."
     }
    ],
    "calling_codes": [
     "591"
    ],
    "tlds": [
     ".bo"
    ],
    "timezones": [
     "UTC-04:00"
    ],
    "borders": [
     "ARG",
     "BRA",
     "CHL",
     "PRY",
     "PER"
    ],
    "cars": {
     "driving_side": "right"
    },
    "landlocked": true,
    "classification": {
     "sovereign": true,
     "un_member": true
    },
    "memberships": {
     "un": true
    },
    "flag": {
     "colors": {
      "prominent": "not a colour",
      "dominant": "#007A33"
     }
    }
   },
   {
    "names": {
     "common": "Bouvet Island",
     "official": "Bouvet Island"
    },
    "codes": {
     "alpha_2": "BV",
     "alpha_3": "BVT"
    },
    "capitals": [],
    "region": "Antarctic",
    "subregion": "",
    "population": 0,
    "area": {
     "kilometers": 49
    },
    "borders": [],
    "landlocked": false,
    "classification": {
     "sovereign": false,
     "un_member": false,
     "dependency": true
    },
    "cars": {
     "driving_side": "sideways"
    }
   },
   {
    "names": {
     "common": "No code"
    },
    "codes": {}
   },
   {
    "names": {},
    "codes": {
     "alpha_2": "XX"
    }
   },
   "a string",
   null,
   {
    "names": {
     "common": "Bad figures"
    },
    "codes": {
     "alpha_2": "ZZ",
     "alpha_3": "ZZZ"
    },
    "population": "12",
    "area": {
     "kilometers": true
    },
    "landlocked": "yes",
    "borders": "USA"
   }
  ],
  "meta": {
   "total": 249,
   "count": 8,
   "limit": 100,
   "offset": 0,
   "more": true
  }
 }
}

// What the demo key answers, whatever it is asked.
var DEMO = {"data": {"_demo": {"message": "You just ran a test against the demo key."}, "objects": [{"names": {"alternates": [], "common": "Canada", "native": {"eng": {"common": "Canada", "official": "Canada"}, "fra": {"common": "Canada", "official": "Canada"}}, "official": "Canada"}, "codes": {"alpha_2": "CA", "alpha_3": "CAN", "ccn3": "124", "cioc": "CAN", "fifa": "CAN", "fips": "CA", "gec": "CA"}, "capitals": [{"attributes": {"administrative": false, "constitutional": false, "executive": false, "judicial": false, "legislative": false, "primary": true}, "coordinates": {"lat": 45.42, "lng": -75.7}, "name": "Ottawa"}], "flag": {"colors": {"dominant": "#fcfaf5", "prominent": "#ff181b"}, "description": "The flag of Canada is composed of a red vertical band on the hoist and fly sides and a central white square that is twice the width of the vertical bands. A large eleven-pointed red maple leaf is centered in the white square.", "emoji": "🇨🇦", "html_entity": "&#127464;&#127462;", "unicode": "U+1F1E8 U+1F1E6", "url_png": "https://flags.restcountries.com/v5/w640/ca.png", "url_svg": "https://flags.restcountries.com/v5/svg/ca.svg"}, "region": "Americas", "subregion": "North America", "area": {"kilometers": 9984670, "miles": 3855101.1}, "borders": ["USA"], "calling_codes": ["1"], "cars": {"driving_side": "right", "signs": ["CDN"]}, "classification": {"dependency": false, "dependency_type": "", "disputed": false, "iso_status": "official", "sovereign": true, "un_member": true, "un_observer": false}, "continents": ["North America"], "coordinates": {"lat": 60, "lng": -95}, "currencies": [{"code": "CAD", "name": "Canadian dollar", "symbol": "$"}], "date": {"academic_year_start": {"day": 1, "month": 9}, "fiscal_year_start": {"corporate": {"basis": "convention", "day": 1, "month": 1}, "government": {"day": 1, "month": 4}, "personal": {"day": 1, "month": 1}}, "start_of_week": "sunday"}, "demonyms": {"eng": {"f": "Canadian", "m": "Canadian"}, "fra": {"f": "Canadienne", "m": "Canadien"}}, "descriptions": {"long": "Canada is a Commonwealth realm with Ottawa as its capital and English and French as official languages. The Canadian dollar is the currency, and energy, minerals, forestry, manufacturing and services support a mostly southern population.", "short": "Canada is a federal parliamentary state in northern North America, second in the world by area."}, "government_type": "Federal parliamentary constitutional monarchy", "landlocked": false, "languages": [{"bcp47": "en", "iso639_1": "en", "iso639_2b": "eng", "iso639_2t": "eng", "iso639_3": "eng", "name": "English", "native_name": "English"}, {"bcp47": "fr", "iso639_1": "fr", "iso639_2b": "fre", "iso639_2t": "fra", "iso639_3": "fra", "name": "French", "native_name": "français"}], "memberships": {"african_union": false, "arab_league": false, "asean": false, "brics": false, "commonwealth": true, "eu": false, "eurozone": false, "g20": true, "g7": true, "nato": true, "oecd": true, "opec": false, "schengen": false, "un": true}, "population": 41798407, "timezones": ["UTC-08:00", "UTC-07:00", "UTC-06:00", "UTC-05:00", "UTC-04:00", "UTC-03:30"], "tlds": [".ca"]}], "meta": {"total": 1}}}

// What a 401 says.
var REFUSED = {"errors": [{"message": "No matching authorization key found.", "code": "authKeyNotFound"}]}
