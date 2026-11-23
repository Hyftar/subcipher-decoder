# Builds the English statistics used by Subcipher.English to score how
# English a decryption looks:
#
#   * priv/english/quadgrams.txt - counts of 4-letter sequences, text reduced
#     to its letters A-Z (spaces and punctuation removed);
#   * priv/english/words.txt - counts of words.
#
#   mix run --no-start scripts/build_english_stats.exs book1.txt book2.txt ...
#
# Each file keeps the most frequent entries; its first line is the total
# count. The shipped files were built from the public-domain prose of NLTK's
# "Project Gutenberg Selections" corpus (Austen, Carroll, Chesterton,
# Melville, Edgeworth, Bryant, Burgess).

paths = System.argv()
if paths == [], do: raise("give the text files to read")

texts = Enum.map(paths, &(&1 |> File.read!() |> String.upcase()))

quadgrams =
  Enum.reduce(texts, %{}, fn text, counts ->
    text
    |> String.replace(~r/[^A-Z]/, "")
    |> String.to_charlist()
    |> Enum.chunk_every(4, 1, :discard)
    |> Enum.reduce(counts, fn quad, acc -> Map.update(acc, List.to_string(quad), 1, &(&1 + 1)) end)
  end)

words =
  Enum.reduce(texts, %{}, fn text, counts ->
    ~r/[A-Z]+/
    |> Regex.scan(text)
    |> Enum.reduce(counts, fn [word], acc -> Map.update(acc, word, 1, &(&1 + 1)) end)
  end)

write = fn counts, name, keep ->
  total = counts |> Map.values() |> Enum.sum()
  top = counts |> Enum.sort_by(fn {k, n} -> {-n, k} end) |> Enum.take(keep)
  out = Path.expand("../priv/english/#{name}", __DIR__)
  File.mkdir_p!(Path.dirname(out))

  File.write!(out, [
    Integer.to_string(total),
    "\n",
    Enum.map(top, fn {k, n} -> [k, " ", Integer.to_string(n), "\n"] end)
  ])

  IO.puts("#{name}: #{map_size(counts)} distinct, #{total} in total; kept #{length(top)}")
end

write.(quadgrams, "quadgrams.txt", 40_000)
# Words seen at least twice (fewer typos and rare names).
write.(words |> Enum.filter(fn {_, n} -> n >= 2 end) |> Map.new(), "words.txt", 30_000)
