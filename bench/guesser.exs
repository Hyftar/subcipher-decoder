# Measures the cipher guesser on encrypted samples (Subcipher.GuesserSamples):
# for each cipher and length, how often it ranks first ("cipher") and how
# often the first guess decodes the text ("text"), and what it is confused
# with.
#
#     MIX_ENV=test mix run --no-start bench/guesser.exs [--deep] [--count 5] [--lengths 20,40,80,150] [--seed 1]
#
# --deep also runs the solvers (slow: seconds per sample).

alias Subcipher.{Guesser, GuesserSamples}

{opts, _, _} =
  OptionParser.parse(System.argv(), strict: [deep: :boolean, count: :integer, lengths: :string, seed: :integer])

deep = Keyword.get(opts, :deep, false)
count = Keyword.get(opts, :count, 5)
seed = Keyword.get(opts, :seed, 1)

lengths =
  opts |> Keyword.get(:lengths, "20,40,80,150") |> String.split(",") |> Enum.map(&String.to_integer/1)

short = fn module -> module |> inspect() |> String.split(".") |> List.last() end

IO.puts("Guesser benchmark: #{count} samples per cell, deep pass #{if deep, do: "on", else: "off"}\n")
IO.puts(String.pad_trailing("cipher", 22) <> Enum.map_join(lengths, &String.pad_leading("#{&1} letters", 16)))

{totals, confusions} =
  Enum.reduce(GuesserSamples.ciphers(), {%{}, %{}}, fn cipher, {totals, confusions} ->
    {cells, confusions} =
      Enum.map_reduce(lengths, confusions, fn letters, confusions ->
        results =
          cipher
          |> GuesserSamples.samples(letters, count, seed)
          |> Task.async_stream(
            fn sample ->
              case Guesser.guess(sample.text, deep: deep) do
                {:ok, %{guesses: [best | _]}} ->
                  {best.cipher, GuesserSamples.decoded?(best.output, sample.plain)}

                _ ->
                  {nil, false}
              end
            end,
            timeout: :infinity
          )
          |> Enum.map(fn {:ok, result} -> result end)

        right = Enum.count(results, fn {guessed, _} -> guessed == cipher end)
        decoded = Enum.count(results, fn {_, decoded?} -> decoded? end)

        confusions =
          for {guessed, _} <- results, guessed != cipher, reduce: confusions do
            acc -> Map.update(acc, {cipher, guessed}, 1, &(&1 + 1))
          end

        {{letters, right, decoded}, confusions}
      end)

    row =
      Enum.map_join(cells, fn {_, right, decoded} ->
        String.pad_leading("#{right}/#{count} · #{decoded}/#{count}", 16)
      end)

    IO.puts(String.pad_trailing(short.(cipher), 22) <> row)

    totals =
      Enum.reduce(cells, totals, fn {letters, right, decoded}, acc ->
        Map.update(acc, letters, {right, decoded}, fn {r, d} -> {r + right, d + decoded} end)
      end)

    {totals, confusions}
  end)

n = count * length(GuesserSamples.ciphers())

IO.puts(
  String.pad_trailing("all", 22) <>
    Enum.map_join(lengths, fn letters ->
      {right, decoded} = totals[letters]
      String.pad_leading("#{round(100 * right / n)}% · #{round(100 * decoded / n)}%", 16)
    end)
)

IO.puts("\n(cells: right cipher · text decoded)\n\nConfusions (truth → guessed: count):")

confusions
|> Enum.sort_by(&elem(&1, 1), :desc)
|> Enum.each(fn {{truth, guessed}, n} ->
  IO.puts("  #{short.(truth)} → #{if guessed, do: short.(guessed), else: "nothing"}: #{n}")
end)
