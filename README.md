# Subcipher

A Phoenix LiveView workbench for cracking ciphers, from text or from pictures of symbols.

1. Choose the cipher (symbol substitution, Caesar, Vigenere, Morse, anagram, and more).
2. Give it its input: the cipher text, or for symbol substitution, pictures (pick, drag &
   drop or paste) in which every symbol is detected and identical symbols are grouped.
3. Decode it: for symbols, click one and type the letter it stands for, and every
   identical symbol is replaced at once. Add more steps when the result is itself
   enciphered.

## Getting started

Requirements: [Nix](https://nixos.org) and Docker.

```sh
nix-shell    # or `nix develop` / direnv: Elixir 1.19 / OTP 28, esbuild, tailwind, node, psql, make
make setup   # starts PostgreSQL 17 in Docker, fetches deps, creates the database, builds assets
make start   # http://localhost:4000
```

`make help` lists every command (`test`, `test-js`, `precommit`, `iex`, `db-up`, `db-down`,
`db-reset`, `psql`, `fixtures`, and others). Targets run in the Nix environment
automatically if you call `make` from outside it.

* Port 5432 already taken? `export POSTGRES_PORT=5433` before `docker compose up`
  (the app reads the same variable).
* `shell.nix` sets `DOCKER_CONTEXT=default` so the database runs on the local Docker
  daemon, which the app reaches through `localhost`.
* Phoenix normally downloads esbuild/tailwind binaries that don't run on NixOS;
  `MIX_ESBUILD_PATH` / `MIX_TAILWIND_PATH` point it at the Nix ones instead.

## How it works

| Step | Where | Code |
| --- | --- | --- |
| Adaptive thresholding, connected components, merging the parts of a symbol (the dot of an `i`, the bars of `=`, detached strokes), 16x16 ink-coverage descriptor | Browser (canvas, no library) | `assets/js/glyph_detector.js`, `assets/js/hooks/glyph_detector_hook.js` |
| Reading order, lines, word breaks | Server | `Subcipher.Ciphers.Analysis.layout/1` |
| Grouping identical symbols (cosine distance on smoothed descriptors + aspect/size) | Server | `Subcipher.Ciphers.Analysis.cluster/2` |
| Puzzles, symbols (letter, ignored), glyphs | PostgreSQL | `Subcipher.Ciphers` |

Detection isn't perfect, so the puzzle page lets you fix it:

* **Merge**: two groups are actually the same symbol.
* **Split this one off**: one occurrence was grouped with the wrong symbol.
* **Ignore**: hide noise or decorations from the text.
* **Grouping tolerance**: re-cluster everything (letters are kept when a new group agrees).

Keyboard shortcuts on the symbols:

* Type a letter to substitute the selected symbol; <kbd>Backspace</kbd> or
  <kbd>Delete</kbd> clears it.
* <kbd>Left</kbd> / <kbd>Right</kbd>: previous / next character of the text.
* <kbd>Up</kbd> / <kbd>Down</kbd> (or <kbd>Shift</kbd>+<kbd>Tab</kbd> / <kbd>Tab</kbd>):
  previous / next symbol of the key.
* <kbd>Esc</kbd>: deselect.

Uploaded pictures are stored in `priv/static/uploads/` (git-ignored). A cipher can span
several pictures; they share the same symbols.

## Decoding steps

The home page lists every cipher; choosing one asks for the input it needs (declared by the
cipher's `input_kinds/0`):

* pictures: only symbol substitution so far. Step 1 is the substitution of the symbols
  detected in the pictures (it can also start from typed symbols instead).
* text: the cipher text is pasted in (and editable on step 1).

Then each step decodes the output of the previous one. The steps are shown as connected
circles at the top of the page: click one to open it (`?step=N` in the URL), or the last one,
**+**, to add a step. A step's cipher can be changed with the selector on the step. Available
ciphers:

* **Symbol substitution**: every distinct character is a symbol; replace each one by the
  letter it stands for (one input per symbol, most frequent first).
* **Letter substitution**: map each letter to another by hand (an alphabet grid showing
  how often each letter appears in the step's input).
* **Caesar cipher**: a shift.
* **Keyword substitution**: the cipher alphabet is a keyword followed by the rest of the
  alphabet.
* **Vigenere cipher**: a Caesar shift that changes with each letter, following a key.
* **Atbash**: the alphabet reversed (A becomes Z, B becomes Y, and so on).
* **Morse code**: letters separated by a space, words by `/`, `|` or several spaces.
* **Letter numbers (A1Z26)**: A = 1 to Z = 26 (or starting from A = 0).
* **Reversed text**: by line, by word or the whole text.
* **Anagram**: the characters become tiles to put back in order: drag and drop, tap two
  tiles, or <kbd>Left</kbd> / <kbd>Right</kbd> on a focused tile; the other tiles bounce
  aside to make room. Spaces are tiles too: the **Spaces** slider (from 0 to the number of
  letters minus 1, by default the clue's) sets how many word breaks the solution has;
  spaces left at either end are ignored.

### Suggestions

Most ciphers suggest up to 5 sets of settings for the step's input, each with the reason it
was suggested and a preview of the result; **Use** applies one.

| Cipher | How suggestions are found |
| --- | --- |
| Caesar | all 26 shifts tried, the 5 with the most English-like letter frequencies kept |
| Vigenere | key length from the index of coincidence (how often letters repeat), then each key letter by frequency analysis; needs about 20 letters |
| Keyword substitution | known keywords tried (`FAITH` from Fallen From Grace, gods of Gielinor, common ones) |
| Letter substitution | frequency match (most frequent letters to E, T, A, O and so on), Caesar and Atbash alphabets |
| Symbol substitution | frequency match; keeping the symbols that are letters already |
| Letter numbers | A = 0 or A = 1, from the numbers present (a 0 or a 26) |
| Reversed text | the three modes, by the English words and letter pairs they give |

Atbash and Morse code have nothing to choose, and anagrams would need a dictionary of NPC
names, so they don't suggest. The symbols of pictures (step 1) get a frequency match too.

### Algorithms

**Make an algorithm** on a puzzle freezes its steps and settings into an algorithm that can
encode and decode any text (`/algorithms/:id`, listed on the home page):

* an **Encode** / **Decode** switch, and the text after each step, from input to result;
* encoding runs the steps backwards with each cipher's `encode/2`. Every cipher has one
  except **Anagram** (its order only fits the text it was solved on), so a puzzle with an
  anagram step can't become an algorithm;
* for a pictures puzzle, the symbol key (a sample glyph per letter) is kept, with copies of
  the pictures: encoding draws the result with those symbols, and decoding takes symbols
  composed on an on-screen keyboard of the key. Letters without a symbol are shown as
  missing.

Its settings can't be changed: edit the puzzle and make a new algorithm instead.

### Solver

Substitutions (the symbols of pictures, symbol substitution and letter substitution) also
have **Try to solve**: `Subcipher.Solver` searches for the letters that make the text read
most like English (simulated annealing with random restarts), in the background, in a
second or two. Its reason says how many of the decoded words are English words.

* It scores letters with English 4-letter sequence frequencies and, when the text has word
  breaks (pictures keep them), words with a dictionary (`Subcipher.English`).
* Letters already set are kept: fix the ones you are sure of, then **Solve again**.
* On English texts encrypted with a random alphabet it solves about 150 letters without
  word breaks, or about 70 with them. Names, codes (fairy ring codes, for example) and a
  symbol detected as two groups (fix it with **Merge**) make it harder.

The statistics in `priv/english/` were built from the public-domain prose of NLTK's
"Project Gutenberg Selections" corpus with `scripts/build_english_stats.exs`.

### Old School RuneScape

The ciphers cover those used in Old School RuneScape, as documented on the
[OSRS Wiki](https://oldschool.runescape.wiki) (each step shows where its cipher appears):

| In the game | Cipher |
| --- | --- |
| Treasure Trails cipher clues, Venom-riddled note (ROT13) | Caesar (the wiki's "+N" shifts mostly decode with a shift of N, sometimes 26 minus N: the step's suggestions include the right one for nearly every clue) |
| Fallen From Grace, Warning note | Keyword substitution, keyword `FAITH` |
| The Writing's on the Wall, Lunar alphabet, VPSG code, Secrets of the North's strange cipher | Symbol alphabets: start from pictures (their keys only exist as images) |
| Easter eggs (bank booths, gravestones, Alliance records, and more) | Morse code |
| Shattered Relics ARG, Crack the Clue III, Beneath Cursed Sands, 2023 Easter event | Letter numbers (A1Z26), Vigenere, Caesar |
| Demonic Pacts League reveal | Vigenere, Atbash, reversed text, Caesar |
| Treasure Trails anagram clues | Anagram |

`test/subcipher/steps/osrs_test.exs` checks the ciphers against the wiki's examples.

Letter ciphers only change the letters A to Z (case kept); anything else passes through,
including the dot shown for symbols that are not deciphered yet.

### Adding a cipher type

1. Create a module implementing `Subcipher.Steps.Cipher` in `lib/subcipher/steps/ciphers/`
   (see the Atbash example in that module's docs): `type/0` (stored in the database, never
   change it), `name/0`, `description/0`, `fields/0` (its parameters) and `decode/2`.
   Optional: `validate/1`, `summary/1`, `suggestions/2` (settings to try, each with the
   reason it was suggested; shown when implemented), `solve/2` (**Try to solve**),
   `encode/2` (the reverse of `decode/2`, needed to be part of an algorithm),
   `osrs_usage/0` (where the cipher appears in the game) and `input_kinds/0` (what it can
   start from, `[:text]` by default).
2. List it in `@ciphers` in `Subcipher.Steps`.

The parameter form is generated from `fields/0`: `:integer` (an input, or a slider with
`control: :range`, whose `max` may depend on the step's input), `:string`, `:select`,
`:letter_map`, `:symbol_map` or `:permutation` fields (see `Subcipher.Steps.Cipher`).
`test/subcipher/steps/ciphers_test.exs` checks every registered cipher against the
behaviour's contract automatically. `Subcipher.Steps.Alphabet` has helpers for letter-wise
ciphers (`map_letters/2`, `english_score/1`).

## Tests

```sh
mix test      # Elixir (analysis, context, LiveViews)
mix test.js   # JS detector, run with Node against the fixtures
mix precommit # compile with warnings as errors, format, both test suites
```

The fixtures in `test/fixtures/` (an enciphered pangram, clean and "phone photo"
versions) are generated by `scripts/make_fixtures.sh`; the JS tests regenerate the
`*.glyphs.json` detection results used by the Elixir tests.
