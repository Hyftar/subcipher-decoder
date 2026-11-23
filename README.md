# Subcipher

A Phoenix LiveView workbench for cracking simple substitution ciphers from a picture.

1. Upload (pick, drag & drop or paste) a picture of the cipher text.
2. Every symbol is detected and identical symbols are grouped together.
3. Click a symbol and type the letter it stands for: every identical symbol is
   replaced at once, until the message is revealed.

## Getting started

Requirements: [Nix](https://nixos.org) and Docker.

```sh
nix-shell    # or `nix develop` / direnv: Elixir 1.19 / OTP 28, esbuild, tailwind, node, psql, make…
make setup   # starts PostgreSQL 17 in Docker, fetches deps, creates the database, builds assets
make start   # http://localhost:4000
```

`make help` lists every command (`test`, `test-js`, `precommit`, `iex`, `db-up`, `db-down`,
`db-reset`, `psql`, `fixtures`…). Targets run in the Nix environment automatically if you
call `make` from outside it.

* Port 5432 already taken? `export POSTGRES_PORT=5433` before `docker compose up`
  (the app reads the same variable).
* `shell.nix` sets `DOCKER_CONTEXT=default` so the database runs on the local Docker
  daemon, which the app reaches through `localhost`.
* Phoenix normally downloads esbuild/tailwind binaries that don't run on NixOS;
  `MIX_ESBUILD_PATH` / `MIX_TAILWIND_PATH` point it at the Nix ones instead.

## How it works

| Step | Where | Code |
| --- | --- | --- |
| Adaptive thresholding, connected components, merging the parts of a symbol (`i`, `=`, `☀`…), 16×16 ink-coverage descriptor | Browser (canvas, no library) | `assets/js/glyph_detector.js`, `assets/js/hooks/glyph_detector_hook.js` |
| Reading order, lines, word breaks | Server | `Subcipher.Ciphers.Analysis.layout/1` |
| Grouping identical symbols (cosine distance on smoothed descriptors + aspect/size) | Server | `Subcipher.Ciphers.Analysis.cluster/2` |
| Puzzles, symbols (letter, ignored), glyphs | PostgreSQL | `Subcipher.Ciphers` |

Detection isn't perfect, so the puzzle page lets you fix it:

* **Merge…** — two groups are actually the same symbol.
* **Split this one off** — one occurrence was grouped with the wrong symbol.
* **Ignore** — hide noise or decorations from the text.
* **Grouping tolerance** — re-cluster everything (letters are kept when a new group agrees).

Keyboard: type a letter to substitute the selected symbol, `⌫` clears, `←`/`→` move to the
previous/next character of the text, `↑`/`↓` (or `Tab`) to the previous/next symbol of the
key, `Esc` deselects.

Uploaded pictures are stored in `priv/static/uploads/` (git-ignored). A cipher can span
several pictures; they share the same symbols.

## Decoding steps

A cipher starts from either **pictures** or **text** (chosen when creating it):

* pictures — step 1 is the substitution of the symbols detected in the pictures (it is the
  only step that can read pictures);
* text — the cipher text is pasted in (and editable on step 1); step 1 can be any cipher.

Then each step decodes the output of the previous one. The steps are shown as connected
circles at the top of the page: click one to open it (`?step=N` in the URL), or the last one,
**+**, to add a step. A step's cipher can be changed with the selector on the step. Available
ciphers:

* **Symbol substitution** — every distinct character is a symbol; replace each one by the
  letter it stands for (one input per symbol, most frequent first).
* **Letter substitution** — map each letter to another by hand (an alphabet grid showing
  how often each letter appears in the step's input).
* **Caesar cipher** — a shift; **Suggest keys** ranks all 26 shifts by how English the
  result looks.
* **Keyword substitution** — the cipher alphabet is a keyword followed by the rest of the
  alphabet.
* **Vigenère cipher** — a Caesar shift that changes with each letter, following a key.
* **Atbash** — the alphabet reversed (A ↔ Z).
* **Morse code** — letters separated by a space, words by `/`, `|` or several spaces.
* **Letter numbers (A1Z26)** — A = 1 … Z = 26 (or A = 0).
* **Reversed text** — by line, by word or the whole text.
* **Anagram** — the characters become tiles to put back in order: drag and drop, tap two
  tiles, or `←`/`→` on a focused tile; the other tiles bounce aside to make room. Spaces are
  tiles too: the **Spaces** slider (0 to letters − 1, by default the clue's) sets how many
  word breaks the solution has; spaces left at either end are ignored.

### Old School RuneScape

The ciphers cover those used in Old School RuneScape, as documented on the
[OSRS Wiki](https://oldschool.runescape.wiki) (each step shows where its cipher appears):

| In the game | Cipher |
| --- | --- |
| Treasure Trails cipher clues, Venom-riddled note (ROT13) | Caesar (the wiki's "+N" shifts mostly decode with a shift of N, sometimes 26 − N: use **Suggest keys**) |
| Fallen From Grace, Warning note | Keyword substitution, keyword `FAITH` |
| The Writing's on the Wall, Lunar alphabet, VPSG code, Secrets of the North's strange cipher | Symbol alphabets: start from pictures (their keys only exist as images) |
| Easter eggs (bank booths, gravestones, Alliance records…) | Morse code |
| Shattered Relics ARG, Crack the Clue III, Beneath Cursed Sands, 2023 Easter event | Letter numbers (A1Z26), Vigenère, Caesar |
| Demonic Pacts League reveal | Vigenère, Atbash, reversed text, Caesar |
| Treasure Trails anagram clues | Anagram |

`test/subcipher/steps/osrs_test.exs` checks the ciphers against the wiki's
examples.

Letter ciphers only change the letters A–Z (case kept); anything else, including `·` for
symbols not deciphered yet, passes through.

### Adding a cipher type

1. Create a module implementing `Subcipher.Steps.Cipher` in `lib/subcipher/steps/ciphers/`
   (see the Atbash example in that module's docs): `type/0` (stored in the database, never
   change it), `name/0`, `description/0`, `fields/0` (its parameters) and `decode/2`;
   optionally `validate/1`, `summary/1` and `candidates/2` (key suggestions).
2. List it in `@ciphers` in `Subcipher.Steps`.

The parameter form is generated from `fields/0`: `:integer` (an input, or a slider with
`control: :range`, whose `max` may depend on the step's input), `:string`, `:select`,
`:letter_map`, `:symbol_map` or `:permutation` fields (see `Subcipher.Steps.Cipher`), and `test/subcipher/steps/ciphers_test.exs` checks every registered cipher
against the behaviour's contract automatically. `Subcipher.Steps.Alphabet` has helpers
for letter-wise ciphers (`map_letters/2`, `english_score/1`).

## Tests

```sh
mix test      # Elixir (analysis, context, LiveViews)
mix test.js   # JS detector, run with Node against the fixtures
mix precommit # compile with warnings as errors, format, both test suites
```

The fixtures in `test/fixtures/` (an enciphered pangram, clean and "phone photo"
versions) are generated by `scripts/make_fixtures.sh`; the JS tests regenerate the
`*.glyphs.json` detection results used by the Elixir tests.
