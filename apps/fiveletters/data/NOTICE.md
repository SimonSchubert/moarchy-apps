# The word lists

Two files, both UPPERCASE, one word per line, five letters, A–Z only, sorted and
deduplicated:

- `answers.txt` — 1,510 words that can be the secret. Common, fair, and every
  one of them a word somebody would use.
- `guesses.txt` — 12,167 words the app will accept as a guess. A superset of the
  answers, and much wider: guessing an obscure word is a legitimate strategy and
  being told "not in word list" for one is the most annoying thing this kind of
  game does.

They come from [Braincup](https://github.com/SimonSchubert/Braincup), where they
were assembled for the same game and the same reason, and they are carried here
verbatim so that both apps stay wrong in the same places if they are wrong at
all.

## Sources

| List | Source |
|---|---|
| answers | NYT Wordle lists (cfreshman gists) filtered to [WordNet](https://wordnet.princeton.edu/) nouns and [en_50k](https://github.com/hermitdave/FrequencyWords) frequency ≥ 200 |
| guesses | the same lists, unfiltered |

The filter is what makes the answers fair: a five-letter string that appears in
a dictionary is not the same thing as a word a person would guess, and a game
whose secret is AALII is a game somebody loses for no reason. The guess list is
deliberately not filtered that way, because the two lists answer two different
questions.

## English only

One language, and the app says so rather than pretending otherwise. A word list
cannot be translated: every language needs its own curated words, its own
alphabet and its own accent policy, all authored together. Braincup ships four
(en, de, fr, nl) and the machinery to add more; this app ships the one, because
a phone app that offered a language picker with nothing behind it would be worse
than one that did not offer it.
