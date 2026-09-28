#!/usr/bin/python3
"""Write a small world to look at: forty countries, their flags, and a record.

An atlas photographs badly against the real thing: the container that takes
the pictures has no route to the internet and no REST Countries key, and the
screen it would draw -- asking for one -- is the screen this app is designed
to show once.

So this writes the three files the app reads (countries.json in the shape
Countries.js keeps, flags/<code>.png, quiz.json) for forty countries whose
flags are stripes, discs and crosses, which a few lines of Python can draw
without an image library. The facts are real, rounded where the world is
still counting; nothing here is fetched. dev/shots runs the app with
MOARCHY_ATLAS_OFFLINE, so no socket is opened, and pins its clock with
MOARCHY_ATLAS_NOW, so "updated 3 days ago" says so every time.

    MOARCHY_ATLAS_DIR=/tmp/atlas python3 apps/atlas/dev/demo.py

MOARCHY_ATLAS_EMPTY=1 writes nothing, for the first-run screen.
"""

from __future__ import annotations

import json
import os
import struct
import sys
import zlib
from pathlib import Path

NOW = 1_790_000_000  # 2026-09-21, a little under a week before the shots' NOW
FETCHED = NOW - 3 * 86400

# code, a3, name, official, capital, region, subregion, population, km2,
# languages, (currency code, name, symbol), calling, tld, borders,
# landlocked, drives, memberships, (lat, lng)
EU = ["EU", "Eurozone", "Schengen"]
W = [
    (
        "AM",
        "ARM",
        "Armenia",
        "Republic of Armenia",
        "Yerevan",
        "Asia",
        "Western Asia",
        3_015_400,
        29_743,
        ["Armenian"],
        ("AMD", "Armenian dram", "֏"),
        "374",
        ".am",
        "AZE GEO IRN TUR",
        True,
        "right",
        [],
        (40, 45),
    ),
    (
        "AT",
        "AUT",
        "Austria",
        "Republic of Austria",
        "Vienna",
        "Europe",
        "Central Europe",
        9_197_213,
        83_871,
        ["German"],
        ("EUR", "Euro", "€"),
        "43",
        ".at",
        "CZE DEU HUN ITA LIE SVK SVN CHE",
        True,
        "right",
        EU + ["OECD"],
        (47.3, 13.3),
    ),
    (
        "BD",
        "BGD",
        "Bangladesh",
        "People's Republic of Bangladesh",
        "Dhaka",
        "Asia",
        "Southern Asia",
        171_466_990,
        147_570,
        ["Bengali"],
        ("BDT", "Bangladeshi taka", "৳"),
        "880",
        ".bd",
        "MMR IND",
        False,
        "left",
        ["Commonwealth"],
        (24, 90),
    ),
    (
        "BE",
        "BEL",
        "Belgium",
        "Kingdom of Belgium",
        "Brussels",
        "Europe",
        "Western Europe",
        11_825_551,
        30_528,
        ["Dutch", "French", "German"],
        ("EUR", "Euro", "€"),
        "32",
        ".be",
        "FRA DEU LUX NLD",
        False,
        "right",
        EU + ["NATO", "OECD"],
        (50.8, 4),
    ),
    (
        "BG",
        "BGR",
        "Bulgaria",
        "Republic of Bulgaria",
        "Sofia",
        "Europe",
        "Southeast Europe",
        6_445_481,
        110_994,
        ["Bulgarian"],
        ("BGN", "Bulgarian lev", "лв"),
        "359",
        ".bg",
        "GRC MKD ROU SRB TUR",
        False,
        "right",
        ["EU", "Schengen", "NATO"],
        (43, 25),
    ),
    (
        "BO",
        "BOL",
        "Bolivia",
        "Plurinational State of Bolivia",
        "Sucre",
        "Americas",
        "South America",
        12_332_252,
        1_098_581,
        ["Spanish", "Aymara", "Guaraní", "Quechua"],
        ("BOB", "Bolivian boliviano", "Bs."),
        "591",
        ".bo",
        "ARG BRA CHL PRY PER",
        True,
        "right",
        [],
        (-17, -65),
    ),
    (
        "BW",
        "BWA",
        "Botswana",
        "Republic of Botswana",
        "Gaborone",
        "Africa",
        "Southern Africa",
        2_359_609,
        582_000,
        ["English", "Tswana"],
        ("BWP", "Botswana pula", "P"),
        "267",
        ".bw",
        "NAM ZAF ZMB ZWE",
        True,
        "left",
        ["African Union", "Commonwealth"],
        (-22, 24),
    ),
    (
        "CH",
        "CHE",
        "Switzerland",
        "Swiss Confederation",
        "Bern",
        "Europe",
        "Western Europe",
        9_002_763,
        41_284,
        ["German", "French", "Italian", "Romansh"],
        ("CHF", "Swiss franc", "Fr."),
        "41",
        ".ch",
        "AUT FRA ITA LIE DEU",
        True,
        "right",
        ["Schengen", "OECD"],
        (47, 8),
    ),
    (
        "CI",
        "CIV",
        "Côte d'Ivoire",
        "Republic of Côte d'Ivoire",
        "Yamoussoukro",
        "Africa",
        "Western Africa",
        31_719_275,
        322_463,
        ["French"],
        ("XOF", "West African CFA franc", "Fr"),
        "225",
        ".ci",
        "BFA GHA GIN LBR MLI",
        False,
        "right",
        ["African Union"],
        (8, -5),
    ),
    (
        "CO",
        "COL",
        "Colombia",
        "Republic of Colombia",
        "Bogotá",
        "Americas",
        "South America",
        52_695_952,
        1_141_748,
        ["Spanish"],
        ("COP", "Colombian peso", "$"),
        "57",
        ".co",
        "BRA ECU PAN PER VEN",
        False,
        "right",
        ["OECD"],
        (4, -72),
    ),
    (
        "DE",
        "DEU",
        "Germany",
        "Federal Republic of Germany",
        "Berlin",
        "Europe",
        "Western Europe",
        83_577_140,
        357_114,
        ["German"],
        ("EUR", "Euro", "€"),
        "49",
        ".de",
        "AUT BEL CZE DNK FRA LUX NLD POL CHE",
        False,
        "right",
        EU + ["NATO", "G7", "G20", "OECD"],
        (51, 9),
    ),
    (
        "DK",
        "DNK",
        "Denmark",
        "Kingdom of Denmark",
        "Copenhagen",
        "Europe",
        "Northern Europe",
        5_992_734,
        43_094,
        ["Danish"],
        ("DKK", "Danish krone", "kr"),
        "45",
        ".dk",
        "DEU",
        False,
        "right",
        ["EU", "Schengen", "NATO", "OECD"],
        (56, 10),
    ),
    (
        "EE",
        "EST",
        "Estonia",
        "Republic of Estonia",
        "Tallinn",
        "Europe",
        "Northern Europe",
        1_374_687,
        45_228,
        ["Estonian"],
        ("EUR", "Euro", "€"),
        "372",
        ".ee",
        "LVA RUS",
        False,
        "right",
        EU + ["NATO", "OECD"],
        (59, 26),
    ),
    (
        "FI",
        "FIN",
        "Finland",
        "Republic of Finland",
        "Helsinki",
        "Europe",
        "Northern Europe",
        5_635_971,
        338_424,
        ["Finnish", "Swedish"],
        ("EUR", "Euro", "€"),
        "358",
        ".fi",
        "NOR SWE RUS",
        False,
        "right",
        EU + ["NATO", "OECD"],
        (64, 26),
    ),
    (
        "FR",
        "FRA",
        "France",
        "French Republic",
        "Paris",
        "Europe",
        "Western Europe",
        68_605_616,
        551_695,
        ["French"],
        ("EUR", "Euro", "€"),
        "33",
        ".fr",
        "AND BEL DEU ITA LUX MCO ESP CHE",
        False,
        "right",
        EU + ["NATO", "G7", "G20", "OECD"],
        (46, 2),
    ),
    (
        "GA",
        "GAB",
        "Gabon",
        "Gabonese Republic",
        "Libreville",
        "Africa",
        "Middle Africa",
        2_469_296,
        267_668,
        ["French"],
        ("XAF", "Central African CFA franc", "Fr"),
        "241",
        ".ga",
        "CMR COG GNQ",
        False,
        "right",
        ["Commonwealth"],
        (-1, 11.75),
    ),
    (
        "GN",
        "GIN",
        "Guinea",
        "Republic of Guinea",
        "Conakry",
        "Africa",
        "Western Africa",
        14_190_612,
        245_857,
        ["French"],
        ("GNF", "Guinean franc", "Fr"),
        "224",
        ".gn",
        "CIV GNB LBR MLI SEN SLE",
        False,
        "right",
        [],
        (11, -10),
    ),
    (
        "HU",
        "HUN",
        "Hungary",
        "Hungary",
        "Budapest",
        "Europe",
        "Central Europe",
        9_584_627,
        93_028,
        ["Hungarian"],
        ("HUF", "Hungarian forint", "Ft"),
        "36",
        ".hu",
        "AUT HRV ROU SRB SVK SVN UKR",
        True,
        "right",
        ["EU", "Schengen", "NATO", "OECD"],
        (47, 20),
    ),
    (
        "ID",
        "IDN",
        "Indonesia",
        "Republic of Indonesia",
        "Jakarta",
        "Asia",
        "South-Eastern Asia",
        281_603_800,
        1_904_569,
        ["Indonesian"],
        ("IDR", "Indonesian rupiah", "Rp"),
        "62",
        ".id",
        "TLS MYS PNG",
        False,
        "left",
        ["ASEAN", "G20"],
        (-5, 120),
    ),
    (
        "IE",
        "IRL",
        "Ireland",
        "Ireland",
        "Dublin",
        "Europe",
        "Northern Europe",
        5_380_300,
        70_273,
        ["English", "Irish"],
        ("EUR", "Euro", "€"),
        "353",
        ".ie",
        "GBR",
        False,
        "left",
        ["EU", "Eurozone", "OECD"],
        (53, -8),
    ),
    (
        "IS",
        "ISL",
        "Iceland",
        "Iceland",
        "Reykjavík",
        "Europe",
        "Northern Europe",
        389_444,
        103_000,
        ["Icelandic"],
        ("ISK", "Icelandic króna", "kr"),
        "354",
        ".is",
        "",
        False,
        "right",
        ["Schengen", "NATO", "OECD"],
        (65, -18),
    ),
    (
        "IT",
        "ITA",
        "Italy",
        "Italian Republic",
        "Rome",
        "Europe",
        "Southern Europe",
        58_934_177,
        301_336,
        ["Italian"],
        ("EUR", "Euro", "€"),
        "39",
        ".it",
        "AUT FRA SMR SVN CHE VAT",
        False,
        "right",
        EU + ["NATO", "G7", "G20", "OECD"],
        (42.8, 12.8),
    ),
    (
        "JP",
        "JPN",
        "Japan",
        "Japan",
        "Tokyo",
        "Asia",
        "Eastern Asia",
        123_802_000,
        377_975,
        ["Japanese"],
        ("JPY", "Japanese yen", "¥"),
        "81",
        ".jp",
        "",
        False,
        "left",
        ["G7", "G20", "OECD"],
        (36, 138),
    ),
    (
        "LA",
        "LAO",
        "Laos",
        "Lao People's Democratic Republic",
        "Vientiane",
        "Asia",
        "South-Eastern Asia",
        7_647_000,
        236_800,
        ["Lao"],
        ("LAK", "Lao kip", "₭"),
        "856",
        ".la",
        "MMR KHM CHN THA VNM",
        True,
        "right",
        ["ASEAN"],
        (18, 105),
    ),
    (
        "LT",
        "LTU",
        "Lithuania",
        "Republic of Lithuania",
        "Vilnius",
        "Europe",
        "Northern Europe",
        2_885_891,
        65_300,
        ["Lithuanian"],
        ("EUR", "Euro", "€"),
        "370",
        ".lt",
        "BLR LVA POL RUS",
        False,
        "right",
        EU + ["NATO", "OECD"],
        (56, 24),
    ),
    (
        "LU",
        "LUX",
        "Luxembourg",
        "Grand Duchy of Luxembourg",
        "Luxembourg",
        "Europe",
        "Western Europe",
        672_050,
        2_586,
        ["Luxembourgish", "French", "German"],
        ("EUR", "Euro", "€"),
        "352",
        ".lu",
        "BEL FRA DEU",
        True,
        "right",
        EU + ["NATO", "OECD"],
        (49.75, 6.17),
    ),
    (
        "MC",
        "MCO",
        "Monaco",
        "Principality of Monaco",
        "Monaco",
        "Europe",
        "Western Europe",
        38_423,
        2.02,
        ["French"],
        ("EUR", "Euro", "€"),
        "377",
        ".mc",
        "FRA",
        False,
        "right",
        [],
        (43.73, 7.4),
    ),
    (
        "ML",
        "MLI",
        "Mali",
        "Republic of Mali",
        "Bamako",
        "Africa",
        "Western Africa",
        22_395_489,
        1_240_192,
        ["French"],
        ("XOF", "West African CFA franc", "Fr"),
        "223",
        ".ml",
        "DZA BFA GIN CIV MRT NER SEN",
        True,
        "right",
        [],
        (17, -4),
    ),
    (
        "MU",
        "MUS",
        "Mauritius",
        "Republic of Mauritius",
        "Port Louis",
        "Africa",
        "Eastern Africa",
        1_261_041,
        2_040,
        ["English", "French", "Mauritian Creole"],
        ("MUR", "Mauritian rupee", "₨"),
        "230",
        ".mu",
        "",
        False,
        "left",
        ["African Union", "Commonwealth"],
        (-20.3, 57.6),
    ),
    (
        "NG",
        "NGA",
        "Nigeria",
        "Federal Republic of Nigeria",
        "Abuja",
        "Africa",
        "Western Africa",
        223_800_000,
        923_768,
        ["English"],
        ("NGN", "Nigerian naira", "₦"),
        "234",
        ".ng",
        "BEN CMR TCD NER",
        False,
        "right",
        ["African Union", "Commonwealth", "OPEC"],
        (10, 8),
    ),
    (
        "NL",
        "NLD",
        "Netherlands",
        "Kingdom of the Netherlands",
        "Amsterdam",
        "Europe",
        "Western Europe",
        17_942_942,
        41_850,
        ["Dutch"],
        ("EUR", "Euro", "€"),
        "31",
        ".nl",
        "BEL DEU",
        False,
        "right",
        EU + ["NATO", "OECD"],
        (52.5, 5.75),
    ),
    (
        "NO",
        "NOR",
        "Norway",
        "Kingdom of Norway",
        "Oslo",
        "Europe",
        "Northern Europe",
        5_550_203,
        323_802,
        ["Norwegian"],
        ("NOK", "Norwegian krone", "kr"),
        "47",
        ".no",
        "FIN SWE RUS",
        False,
        "right",
        ["Schengen", "NATO", "OECD"],
        (62, 10),
    ),
    (
        "PE",
        "PER",
        "Peru",
        "Republic of Peru",
        "Lima",
        "Americas",
        "South America",
        34_350_244,
        1_285_216,
        ["Spanish", "Aymara", "Quechua"],
        ("PEN", "Peruvian sol", "S/"),
        "51",
        ".pe",
        "BOL BRA CHL COL ECU",
        False,
        "right",
        [],
        (-10, -76),
    ),
    (
        "PL",
        "POL",
        "Poland",
        "Republic of Poland",
        "Warsaw",
        "Europe",
        "Central Europe",
        37_636_508,
        312_696,
        ["Polish"],
        ("PLN", "Polish złoty", "zł"),
        "48",
        ".pl",
        "BLR CZE DEU LTU RUS SVK UKR",
        False,
        "right",
        ["EU", "Schengen", "NATO", "OECD"],
        (52, 20),
    ),
    (
        "PW",
        "PLW",
        "Palau",
        "Republic of Palau",
        "Ngerulmud",
        "Oceania",
        "Micronesia",
        16_733,
        459,
        ["English", "Palauan"],
        ("USD", "United States dollar", "$"),
        "680",
        ".pw",
        "",
        False,
        "right",
        [],
        (7.5, 134.5),
    ),
    (
        "RO",
        "ROU",
        "Romania",
        "Romania",
        "Bucharest",
        "Europe",
        "Southeast Europe",
        19_036_031,
        238_391,
        ["Romanian"],
        ("RON", "Romanian leu", "lei"),
        "40",
        ".ro",
        "BGR HUN MDA SRB UKR",
        False,
        "right",
        ["EU", "Schengen", "NATO"],
        (46, 25),
    ),
    (
        "RU",
        "RUS",
        "Russia",
        "Russian Federation",
        "Moscow",
        "Europe",
        "Eastern Europe",
        146_028_325,
        17_098_246,
        ["Russian"],
        ("RUB", "Russian ruble", "₽"),
        "7",
        ".ru",
        "AZE BLR CHN EST FIN GEO KAZ PRK LVA LTU MNG NOR POL UKR",
        False,
        "right",
        ["G20", "BRICS"],
        (60, 100),
    ),
    (
        "SE",
        "SWE",
        "Sweden",
        "Kingdom of Sweden",
        "Stockholm",
        "Europe",
        "Northern Europe",
        10_588_401,
        450_295,
        ["Swedish"],
        ("SEK", "Swedish krona", "kr"),
        "46",
        ".se",
        "FIN NOR",
        False,
        "right",
        ["EU", "Schengen", "NATO", "OECD"],
        (62, 15),
    ),
    (
        "SL",
        "SLE",
        "Sierra Leone",
        "Republic of Sierra Leone",
        "Freetown",
        "Africa",
        "Western Africa",
        8_908_040,
        71_740,
        ["English"],
        ("SLE", "Sierra Leonean leone", "Le"),
        "232",
        ".sl",
        "GIN LBR",
        False,
        "right",
        ["African Union", "Commonwealth"],
        (8.5, -11.5),
    ),
    (
        "TD",
        "TCD",
        "Chad",
        "Republic of Chad",
        "N'Djamena",
        "Africa",
        "Middle Africa",
        18_278_568,
        1_284_000,
        ["Arabic", "French"],
        ("XAF", "Central African CFA franc", "Fr"),
        "235",
        ".td",
        "CMR CAF LBY NER NGA SDN",
        True,
        "right",
        ["African Union"],
        (15, 19),
    ),
    (
        "TH",
        "THA",
        "Thailand",
        "Kingdom of Thailand",
        "Bangkok",
        "Asia",
        "South-Eastern Asia",
        65_951_210,
        513_120,
        ["Thai"],
        ("THB", "Thai baht", "฿"),
        "66",
        ".th",
        "MMR KHM LAO MYS",
        False,
        "left",
        ["ASEAN"],
        (15, 100),
    ),
    (
        "UA",
        "UKR",
        "Ukraine",
        "Ukraine",
        "Kyiv",
        "Europe",
        "Eastern Europe",
        37_000_000,
        603_550,
        ["Ukrainian"],
        ("UAH", "Ukrainian hryvnia", "₴"),
        "380",
        ".ua",
        "BLR HUN MDA POL ROU RUS SVK",
        False,
        "right",
        [],
        (49, 32),
    ),
    (
        "YE",
        "YEM",
        "Yemen",
        "Republic of Yemen",
        "Sana'a",
        "Asia",
        "Western Asia",
        34_449_825,
        527_968,
        ["Arabic"],
        ("YER", "Yemeni rial", "﷼"),
        "967",
        ".ye",
        "OMN SAU",
        False,
        "right",
        ["Arab League"],
        (15, 48),
    ),
]

NATIVE = {
    "DE": ["Deutschland"],
    "FR": [],
    "IT": ["Italia"],
    "JP": ["日本"],
    "FI": ["Suomi"],
    "SE": ["Sverige"],
    "NO": ["Norge", "Noreg"],
    "PL": ["Polska"],
    "HU": ["Magyarország"],
    "AT": ["Österreich"],
    "CH": ["Schweiz", "Suisse", "Svizzera", "Svizra"],
    "NL": ["Nederland"],
    "IS": ["Ísland"],
    "DK": ["Danmark"],
    "RU": ["Россия"],
    "UA": ["Україна"],
    "TH": ["ประเทศไทย"],
}

ABOUT = {
    "DE": (
        "Germany is a federal parliamentary republic in central Europe with Berlin as its capital and "
        "German as its official language. The euro is the currency, and manufacturing, engineering, "
        "chemicals and services make it Europe's largest economy."
    ),
    "JP": (
        "Japan is an island country in East Asia, a constitutional monarchy with Tokyo as its capital. "
        "Most of its people live on the coastal plains of four main islands."
    ),
    "FR": (
        "France is a unitary semi-presidential republic in western Europe with Paris as its capital "
        "and French as its official language."
    ),
}

FLAG_ABOUT = {
    "DE": "The flag of Germany is composed of three equal horizontal bands of black, red and gold.",
    "JP": "The flag of Japan features a crimson-red circle at the center of a white field.",
    "FR": "The flag of France is composed of three equal vertical bands of blue, white and red.",
}

TIMEZONES = {
    "DE": ["UTC+01:00"],
    "JP": ["UTC+09:00"],
    "FR": ["UTC+01:00"],
    "RU": [
        "UTC+02:00",
        "UTC+03:00",
        "UTC+04:00",
        "UTC+05:00",
        "UTC+06:00",
        "UTC+07:00",
        "UTC+08:00",
        "UTC+09:00",
        "UTC+10:00",
        "UTC+11:00",
        "UTC+12:00",
    ],
}
DEMONYM = {"DE": "German", "JP": "Japanese", "FR": "French"}

# --- the flags -----------------------------------------------------------

C = {
    "black": "000000",
    "white": "ffffff",
    "de_red": "dd0000",
    "de_gold": "ffce00",
    "fr_blue": "002654",
    "fr_red": "ce1126",
    "it_green": "009246",
    "it_red": "ce2b37",
    "ie_green": "169b62",
    "ie_orange": "ff883e",
    "be_yellow": "fdda24",
    "be_red": "ef3340",
    "ro_blue": "002b7f",
    "ro_yellow": "fcd116",
    "ro_red": "ce1126",
    "td_blue": "002664",
    "td_yellow": "fecb00",
    "td_red": "c60c30",
    "green": "14b53a",
    "gn_red": "ce1126",
    "ml_green": "14b53a",
    "ci_orange": "f77f00",
    "ci_green": "009e60",
    "ng_green": "008751",
    "pe_red": "d91023",
    "pl_red": "dc143c",
    "ua_blue": "0057b7",
    "ua_yellow": "ffd700",
    "id_red": "ff0000",
    "mc_red": "ce1126",
    "jp_red": "bc002d",
    "bd_green": "006a4e",
    "bd_red": "f42a41",
    "pw_blue": "0099ff",
    "pw_yellow": "ffde00",
    "la_red": "ce1126",
    "la_blue": "002868",
    "se_blue": "006aa7",
    "se_yellow": "fecc02",
    "fi_blue": "002f6c",
    "dk_red": "c8102e",
    "no_red": "ba0c2f",
    "no_blue": "00205b",
    "is_blue": "02529c",
    "is_red": "dc1e35",
    "th_red": "a51931",
    "th_blue": "2d2a4a",
    "ch_red": "da291c",
    "mu_red": "ea2839",
    "mu_blue": "1a206d",
    "mu_yellow": "ffd500",
    "mu_green": "00a551",
    "bw_blue": "75aadb",
    "ru_blue": "0039a6",
    "ru_red": "d52b1e",
    "nl_red": "ae1c28",
    "nl_blue": "21468b",
    "at_red": "c8102e",
    "hu_red": "ce2939",
    "hu_green": "477050",
    "bg_green": "00966e",
    "bg_red": "d62612",
    "ee_blue": "0072ce",
    "lt_yellow": "fdb913",
    "lt_green": "006a44",
    "lt_red": "c1272d",
    "lu_red": "ea141d",
    "lu_blue": "51add4",
    "ye_red": "ce1126",
    "sl_green": "1eb53a",
    "sl_blue": "0072c6",
    "ga_green": "009e60",
    "ga_yellow": "fcd116",
    "ga_blue": "3a75c4",
    "am_red": "d90012",
    "am_blue": "0033a0",
    "am_orange": "f2a800",
    "bo_red": "da291c",
    "bo_yellow": "f4e400",
    "bo_green": "007a33",
    "co_yellow": "fcd116",
    "co_blue": "003893",
    "co_red": "ce1126",
}


def rgb(name):
    h = C.get(name, name)
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def hstripes(*bands):
    """[(colour, weight)] top to bottom."""
    total = sum(w for _, w in bands)

    def at(x, y, w, h):
        acc = 0
        for colour, weight in bands:
            acc += weight
            if y < h * acc / total:
                return rgb(colour)
        return rgb(bands[-1][0])

    return at


def vstripes(*bands):
    total = sum(w for _, w in bands)

    def at(x, y, w, h):
        acc = 0
        for colour, weight in bands:
            acc += weight
            if x < w * acc / total:
                return rgb(colour)
        return rgb(bands[-1][0])

    return at


def disc(field, colour, cx=0.5, r=0.3):
    base = field if callable(field) else (lambda x, y, w, h: rgb(field))

    def at(x, y, w, h):
        if (x - w * cx) ** 2 + (y - h / 2) ** 2 <= (h * r) ** 2:
            return rgb(colour)
        return base(x, y, w, h)

    return at


def nordic(field, cross, border=None, bar=0.25, inner=0.125):
    """A Scandinavian cross: the upright at 3/8 of the width."""

    def at(x, y, w, h):
        ux, uy = w * 0.36, h / 2
        if border:
            if abs(x - ux) < h * inner / 2 or abs(y - uy) < h * inner / 2:
                return rgb(cross)
            if abs(x - ux) < h * bar / 2 or abs(y - uy) < h * bar / 2:
                return rgb(border)
            return rgb(field)
        if abs(x - ux) < h * bar / 2 or abs(y - uy) < h * bar / 2:
            return rgb(cross)
        return rgb(field)

    return at


def swiss(x, y, w, h):
    arm, reach = h * 0.2 / 2, h * 0.6 / 2
    cx, cy = w / 2, h / 2
    if (abs(x - cx) < arm and abs(y - cy) < reach) or (
        abs(y - cy) < arm and abs(x - cx) < reach
    ):
        return rgb("white")
    return rgb("ch_red")


def botswana(x, y, w, h):
    d = abs(y - h / 2)
    if d < h * 0.1:
        return rgb("black")
    if d < h * 0.14:
        return rgb("white")
    return rgb("bw_blue")


FLAGS = {
    "DE": (5 / 3, hstripes(("black", 1), ("de_red", 1), ("de_gold", 1))),
    "RU": (3 / 2, hstripes(("white", 1), ("ru_blue", 1), ("ru_red", 1))),
    "NL": (3 / 2, hstripes(("nl_red", 1), ("white", 1), ("nl_blue", 1))),
    "AT": (3 / 2, hstripes(("at_red", 1), ("white", 1), ("at_red", 1))),
    "HU": (2, hstripes(("hu_red", 1), ("white", 1), ("hu_green", 1))),
    "BG": (5 / 3, hstripes(("white", 1), ("bg_green", 1), ("bg_red", 1))),
    "EE": (11 / 7, hstripes(("ee_blue", 1), ("black", 1), ("white", 1))),
    "LT": (5 / 3, hstripes(("lt_yellow", 1), ("lt_green", 1), ("lt_red", 1))),
    "LU": (5 / 3, hstripes(("lu_red", 1), ("white", 1), ("lu_blue", 1))),
    "YE": (3 / 2, hstripes(("ye_red", 1), ("white", 1), ("black", 1))),
    "SL": (3 / 2, hstripes(("sl_green", 1), ("white", 1), ("sl_blue", 1))),
    "GA": (4 / 3, hstripes(("ga_green", 1), ("ga_yellow", 1), ("ga_blue", 1))),
    "AM": (2, hstripes(("am_red", 1), ("am_blue", 1), ("am_orange", 1))),
    "BO": (22 / 15, hstripes(("bo_red", 1), ("bo_yellow", 1), ("bo_green", 1))),
    "CO": (3 / 2, hstripes(("co_yellow", 2), ("co_blue", 1), ("co_red", 1))),
    "TH": (
        3 / 2,
        hstripes(
            ("th_red", 1), ("white", 1), ("th_blue", 2), ("white", 1), ("th_red", 1)
        ),
    ),
    "MU": (
        3 / 2,
        hstripes(("mu_red", 1), ("mu_blue", 1), ("mu_yellow", 1), ("mu_green", 1)),
    ),
    "PL": (8 / 5, hstripes(("white", 1), ("pl_red", 1))),
    "UA": (3 / 2, hstripes(("ua_blue", 1), ("ua_yellow", 1))),
    "ID": (3 / 2, hstripes(("id_red", 1), ("white", 1))),
    "MC": (5 / 4, hstripes(("mc_red", 1), ("white", 1))),
    "FR": (3 / 2, vstripes(("fr_blue", 1), ("white", 1), ("fr_red", 1))),
    "IT": (3 / 2, vstripes(("it_green", 1), ("white", 1), ("it_red", 1))),
    "IE": (2, vstripes(("ie_green", 1), ("white", 1), ("ie_orange", 1))),
    "BE": (15 / 13, vstripes(("black", 1), ("be_yellow", 1), ("be_red", 1))),
    "RO": (3 / 2, vstripes(("ro_blue", 1), ("ro_yellow", 1), ("ro_red", 1))),
    "TD": (3 / 2, vstripes(("td_blue", 1), ("td_yellow", 1), ("td_red", 1))),
    "ML": (3 / 2, vstripes(("ml_green", 1), ("ro_yellow", 1), ("gn_red", 1))),
    "GN": (3 / 2, vstripes(("gn_red", 1), ("ro_yellow", 1), ("ml_green", 1))),
    "CI": (3 / 2, vstripes(("ci_orange", 1), ("white", 1), ("ci_green", 1))),
    "NG": (2, vstripes(("ng_green", 1), ("white", 1), ("ng_green", 1))),
    "PE": (3 / 2, vstripes(("pe_red", 1), ("white", 1), ("pe_red", 1))),
    "JP": (3 / 2, disc("white", "jp_red", r=0.3)),
    "BD": (5 / 3, disc("bd_green", "bd_red", cx=0.45, r=1 / 3)),
    "PW": (8 / 5, disc("pw_blue", "pw_yellow", cx=0.45, r=0.3)),
    "LA": (
        3 / 2,
        disc(hstripes(("la_red", 1), ("la_blue", 2), ("la_red", 1)), "white", r=0.2),
    ),
    "SE": (8 / 5, nordic("se_blue", "se_yellow", bar=0.2)),
    "FI": (18 / 11, nordic("white", "fi_blue", bar=3 / 11)),
    "DK": (37 / 28, nordic("dk_red", "white", bar=4 / 28)),
    "NO": (
        22 / 16,
        nordic("no_red", "no_blue", border="white", bar=4 / 16, inner=2 / 16),
    ),
    "IS": (
        25 / 18,
        nordic("is_blue", "is_red", border="white", bar=4 / 18, inner=2 / 18),
    ),
    "CH": (1, swiss),
    "BW": (3 / 2, botswana),
}


# The flags with a curve in them, which are the only ones worth the time.
ROUND = {"JP", "BD", "PW", "LA"}


def png(path: Path, width: int, height: int, at, smooth: bool = False) -> None:
    """With `smooth`, two samples a pixel each way, so a disc has an edge rather than steps."""
    offsets = (0.25, 0.75) if smooth else (0.5,)
    n = len(offsets) ** 2
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            acc = [0, 0, 0]
            for sy in offsets:
                for sx in offsets:
                    c = at(x + sx, y + sy, width, height)
                    acc[0] += c[0]
                    acc[1] += c[1]
                    acc[2] += c[2]
            rows += bytes(v // n for v in acc)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    blob = b"\x89PNG\r\n\x1a\n"
    blob += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    blob += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    blob += chunk(b"IEND", b"")
    path.write_bytes(blob)


def tint(code: str) -> str:
    """The flag's strongest colour that is not white or black, as REST Countries' `prominent`."""
    ratio, at = FLAGS[code]
    best, score = "", -1.0
    h = 40
    w = round(h * ratio)
    seen = {}
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            c = at(x + 0.5, y + 0.5, w, h)
            seen[c] = seen.get(c, 0) + 1
    for c, n in seen.items():
        spread = max(c) - min(c)
        if spread < 40:
            continue
        if n * spread > score:
            best, score = "#%02x%02x%02x" % c, n * spread
    return best


def country(row) -> dict:
    (
        code,
        a3,
        name,
        official,
        capital,
        region,
        subregion,
        population,
        area,
        languages,
        cur,
        calling,
        tld,
        borders,
        landlocked,
        drives,
        memberships,
        (lat, lng),
    ) = row
    return {
        "id": code,
        "code": code,
        "a3": a3,
        "name": name,
        "official": official,
        "native": NATIVE.get(code, []),
        "capitals": [capital],
        "capitalAt": None,
        "region": region,
        "subregion": subregion,
        "population": population,
        "area": area,
        "lat": lat,
        "lng": lng,
        "languages": languages,
        "currencies": [{"code": cur[0], "name": cur[1], "symbol": cur[2]}],
        "calling": [calling],
        "tlds": [tld],
        "timezones": TIMEZONES.get(code, []),
        "borders": borders.split(),
        "drives": drives,
        "landlocked": landlocked,
        "sovereign": True,
        "un": True,
        "memberships": memberships,
        "demonym": DEMONYM.get(code, ""),
        "about": ABOUT.get(code, ""),
        "flagAbout": FLAG_ABOUT.get(code, ""),
        "tint": tint(code),
        "weekStarts": "sunday" if code in ("JP", "TH", "PE", "CO", "BO") else "monday",
    }


def main() -> int:
    target = os.environ.get("MOARCHY_ATLAS_DIR")
    if not target:
        print(
            "set MOARCHY_ATLAS_DIR first -- refusing to touch a real atlas",
            file=sys.stderr,
        )
        return 2
    if os.environ.get("MOARCHY_ATLAS_EMPTY"):
        return 0
    out = Path(target)
    flags = out / "flags"
    flags.mkdir(parents=True, exist_ok=True)
    world = sorted((country(r) for r in W), key=lambda c: c["name"])
    (out / "countries.json").write_text(
        json.dumps(
            {"schema": 1, "fetched": FETCHED, "countries": world}, ensure_ascii=False
        )
        + "\n",
        encoding="utf-8",
    )
    for code, (ratio, at) in FLAGS.items():
        width = 320
        png(
            flags / f"{code.lower()}.png",
            width,
            round(width / ratio),
            at,
            smooth=code in ROUND,
        )
    (out / "quiz.json").write_text(
        json.dumps(
            {
                "schema": 1,
                "rounds": 14,
                "asked": 140,
                "right": 109,
                "best": {
                    "flags:world": {"score": 9, "total": 10},
                    "capitals:world": {"score": 7, "total": 10},
                    "find:Europe": {"score": 10, "total": 10},
                },
            },
            indent=1,
        )
        + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
