defmodule Subcipher.Steps.OsrsTest do
  @moduledoc """
  Ciphers as used in Old School RuneScape, with examples (cipher text and
  solution) from the OSRS Wiki.
  """
  use ExUnit.Case, async: true

  alias Subcipher.Steps

  alias Subcipher.Steps.Ciphers.{
    Anagram,
    Caesar,
    KeywordSubstitution,
    LetterNumbers,
    Morse,
    Reverse,
    Vigenere
  }

  # https://oldschool.runescape.wiki/w/Treasure_Trails/Guide/Ciphers
  # The wiki lists every shift as "+N", but most clues decode by shifting
  # back N and a few by shifting forward (Captain Harlan): forward 1 is a
  # Caesar shift of 25.
  @cipher_clues [
    {"ESBZOPS QJH QFO", 1, "DRAYNOR PIG PEN"},
    {"BMJ UIF LFCBC TFMMFS", 1, "ALI THE KEBAB SELLER"},
    {"BZOSZHM GZQKZM", 25, "CAPTAIN HARLAN"},
    {"ECRVCKP MJCNGF", 2, "CAPTAIN KHALED"},
    {"GUHCHO", 3, "DREZEL"},
    {"BXJA UNJMNA YRCAR", 9, "SOAR LEADER PITRI"},
    {"OVEXON", 10, "ELUNED"},
    {"UZZU MUJHRKYYKJ", 6, "OTTO GODBLESSED"},
    {"VTYR APCNTGLW", 11, "KING PERCIVAL"},
    {"ZSBKDO ZODO", 10, "PIRATE PETE"},
    {"ZCZL", 25, "ADAM"}
  ]

  describe "Caesar" do
    test "Treasure Trails cipher clues" do
      for {clue, shift, npc} <- @cipher_clues do
        assert Caesar.decode(clue, %{shift: shift}) == npc, "#{clue} (shift #{shift})"
      end
    end

    test "the right shift is among the suggestions of every clue" do
      for {clue, shift, _npc} <- @cipher_clues do
        shifts = for %{params: %{shift: s}} <- Caesar.candidates(clue, %{}), do: s
        assert shift in shifts
      end
    end

    test "Venom-riddled note (ROT13)" do
      # https://oldschool.runescape.wiki/w/Venom-riddled_note
      assert Caesar.decode("Uryyb fgenatre.", %{shift: 13}) == "Hello stranger."
    end

    test "Demonic Pacts League, clues to the right (shift 15)" do
      assert Caesar.decode("Bn egtkxdjh udgb lph heaxi xcid ild.", %{shift: 15}) ==
               "My previous form was split into two."
    end

    test "Shattered Relics League ARG, Lighthouse river clue (shifts 4, 9, 5)" do
      # https://oldschool.runescape.wiki/w/Runestone_basalt
      assert Caesar.decode("mrzivherxhitxlwviqemrwjsyvasvhw", %{shift: 4}) ==
               "inverdantdepthsremainsfourwords"

      assert Caesar.decode("byxtnwkhjexrlndwqnjam", %{shift: 9}) == "spokenbyavoiceunheard"

      assert Caesar.decode("fszrgjwtkhqzjxqnjzsinxyzwgji", %{shift: 5}) ==
               "anumberofclueslieundisturbed"
    end
  end

  test "Keyword substitution: Fallen From Grace, Warning note (keyword FAITH)" do
    # https://oldschool.runescape.wiki/w/Fallen_From_Grace
    # https://oldschool.runescape.wiki/w/Warning_note_(Fallen_From_Grace)
    assert KeywordSubstitution.cipher_alphabet("FAITH") == "FAITHBCDEGJKLMNOPQRSUVWXYZ"

    note = """
    RSFQSEMC WESD RUMQERH,
    SDQNUCD SN RUMRHS,
    FMT FR SDH LNNM DFMCR KNW,
    EM SDH RNUSDHQM RJY,
    WH WEKK WFSID NVHQ DHQ.
    """

    assert KeywordSubstitution.decode(note, %{keyword: "FAITH"}) == """
           STARTING WITH SUNRISE,
           THROUGH TO SUNSET,
           AND AS THE MOON HANGS LOW,
           IN THE SOUTHERN SKY,
           WE WILL WATCH OVER HER.
           """
  end

  test "Vigenère: Shattered Relics League ARG (runestone basalt)" do
    # https://oldschool.runescape.wiki/w/Runestone_basalt
    assert Vigenere.decode("FHXSPLZLOUCUGS", %{key: "jatoexugad"}) == "WHEELOFFORTUNE"
    assert Vigenere.decode("MOYQWVL", %{key: "THUMBNAILLARGE"}) == "THEEVIL"
    assert Vigenere.decode("XJFXNLN", %{key: "ECBSZXCWUG"}) == "THEFOOL"

    assert Vigenere.decode("soexttymsybhgmohpvpoidweylbrpvjczimnruxhvrlsemygnlvk", %{
             key: "WHEELOFFORTUNE"
           }) == "whatifthehintisalreadyinfrontofyouhiddeninplainsight"
  end

  test "Morse code easter eggs" do
    # https://oldschool.runescape.wiki/w/Morse_code
    assert Morse.decode("--. . - --. ..- -..", %{}) == "GETGUD"
    assert Morse.decode("-.. . .- - ....", %{}) == "DEATH"
    assert Morse.decode(".-. --- .", %{}) == "ROE"
    # Yama contracts: the in-game A (.-) was engraved as N (-.).
    assert Morse.decode("-.-. --- -. - .-. -. -.-. -", %{}) == "CONTRNCT"
    # Words, other dot/dash characters, unknown codes, non-Morse lines.
    assert Morse.decode("••• ––– •••  ••• / ........\nnot morse", %{}) == "SOS S ·\nnot morse"
  end

  test "Letter numbers (A1Z26)" do
    # https://oldschool.runescape.wiki/w/2023_Easter_event
    assert LetterNumbers.decode("8 1 16 16 25 | 5 1 19 20 5 18", %{first: "1"}) ==
             "HAPPY EASTER"

    # Beneath Cursed Sands chest: Akhem = 1, 11, 8, 5, 13.
    assert LetterNumbers.decode("1, 11, 8, 5, 13", %{first: "1"}) == "AKHEM"
    assert LetterNumbers.decode("0 25 27", %{first: "0"}) == "AZ·"
    assert LetterNumbers.decode("Hello 12", %{first: "1"}) == "Hello 12"
  end

  test "Reversed text: names spelled backwards" do
    assert Reverse.decode("Yenrab Lahsram", %{mode: "words"}) == "barneY marshaL"
    assert Reverse.decode("ab cd\nef", %{mode: "lines"}) == "dc ba\nfe"
    assert Reverse.decode("ab\ncd", %{mode: "text"}) == "dc\nba"
  end

  test "steps chain like the in-game puzzles: numbers, then Vigenère" do
    {:ok, numbers} = Steps.fetch_cipher("letter_numbers")
    {:ok, vigenere} = Steps.fetch_cipher("vigenere")

    # MOYQWVL as letter numbers, then the Harmony clue's key.
    letters = numbers.decode("13 15 25 17 23 22 12", %{first: "1"})
    assert letters == "MOYQWVL"
    assert vigenere.decode(letters, %{key: "THUMBNAILLARGE"}) == "THEEVIL"
  end

  describe "Anagram" do
    # https://oldschool.runescape.wiki/w/Treasure_Trails/Guide/Anagrams
    @anagram_clues [
      {"AN EARL", "RANAEL"},
      {"CARPET AHOY", "APOTHECARY"},
      {"I CORD", "DORIC"},
      {"DIM THARN", "MANDRITH"}
    ]

    # The order of the clue's tiles spelling `solution`, spaces last: what
    # the user builds by dragging the tiles.
    defp order_for(clue, solution) do
      tiles = clue |> Anagram.tiles() |> Enum.with_index()

      {order, rest} =
        solution
        |> String.graphemes()
        |> Enum.reduce({[], tiles}, fn char, {order, rest} ->
          {_, i} = found = Enum.find(rest, fn {t, _} -> t == char end)
          {[i | order], List.delete(rest, found)}
        end)

      # Only spaces may be left: the clue uses exactly the solution's letters.
      assert Enum.all?(rest, fn {t, _} -> t == " " end),
             "#{clue} is not an anagram of #{solution}"

      (Enum.reverse(order) ++ Enum.map(rest, &elem(&1, 1))) |> Enum.join(",")
    end

    test "Treasure Trails anagram clues" do
      for {clue, npc} <- @anagram_clues do
        assert Anagram.decode(clue, %{order: order_for(clue, npc)}) == npc
      end
    end

    test "is the text as it is until rearranged" do
      assert Anagram.decode("AN EARL", %{order: ""}) == "AN EARL"
    end

    test "survives the input changing under it" do
      # Unknown positions dropped, missing ones appended in order.
      assert Anagram.resolve_order("9,2,0", 4) == [2, 0, 1, 3]
      assert Anagram.decode("abc", %{order: "2,9"}) == "cab"
    end

    test "the number of spaces is a setting, from 0 to letters − 1" do
      # One word from a two-word clue: no space tile at all.
      assert Anagram.tiles("CARPET AHOY", 0) |> Enum.join() == "CARPETAHOY"
      order = "1,3,8,5,7,4,0,6,2,9"
      assert Anagram.decode("CARPET AHOY", %{order: order, spaces: 0}) == "APOTHECARY"
      assert Anagram.decode("CARPET AHOY", %{order: "", spaces: 0}) == "CARPETAHOY"

      # More words than the clue: extra space tiles come last.
      assert Anagram.tiles("AN EARL", 2) |> Enum.join() == "AN EARL "
      assert Anagram.decode("AN EARL", %{order: "0,1,2,3,7,4,5,6", spaces: 2}) == "AN E ARL"

      # Clamped to letters − 1; nil follows the input (one per word gap).
      assert Anagram.max_spaces("I CORD") == 4
      assert Anagram.space_count("I CORD", 99) == 4
      assert Anagram.space_count("I CORD", nil) == 1
      assert Anagram.space_count("A", nil) == 0

      assert Steps.params_changeset("anagram", %{"spaces" => "2"}).valid?
      assert Steps.params_changeset("anagram", %{"spaces" => ""}).valid?
      refute Steps.params_changeset("anagram", %{"spaces" => "-1"}).valid?
    end

    test "orders are validated" do
      assert Steps.params_changeset("anagram", %{"order" => "2,0,1"}).valid?
      refute Steps.params_changeset("anagram", %{"order" => "2,0,0"}).valid?
      refute Steps.params_changeset("anagram", %{"order" => "a,b"}).valid?
    end
  end
end
