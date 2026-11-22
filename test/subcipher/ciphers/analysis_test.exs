defmodule Subcipher.Ciphers.AnalysisTest do
  use ExUnit.Case, async: true

  import Subcipher.CipherFixtures
  alias Subcipher.Ciphers.Analysis

  describe "parse_detection/1" do
    test "decodes glyphs" do
      assert {:ok, [glyph | _] = glyphs} = Analysis.parse_detection(detection_payload())
      assert length(glyphs) == length(pangram_letters())
      assert byte_size(glyph.features) == 256
    end

    test "rejects invalid payloads" do
      f = Base.encode64(:binary.copy(<<0>>, 256))
      assert {:error, :no_glyphs} = Analysis.parse_detection(%{"glyphs" => []})
      assert {:error, :invalid_payload} = Analysis.parse_detection(%{})

      for bad <- [
            %{"x" => 1, "y" => 1, "w" => 0, "h" => 1, "f" => f},
            %{"x" => -1, "y" => 1, "w" => 1, "h" => 1, "f" => f},
            %{"x" => 1, "y" => 1, "w" => 1, "h" => 1, "f" => "not base64"},
            %{"x" => 1, "y" => 1, "w" => 1, "h" => 1, "f" => Base.encode64("short")},
            %{"x" => "1", "y" => 1, "w" => 1, "h" => 1, "f" => f}
          ] do
        assert {:error, :invalid_glyph} = Analysis.parse_detection(%{"glyphs" => [bad]})
      end
    end
  end

  describe "layout/1" do
    for name <- ~w(pangram_clean pangram_photo) do
      test "recovers lines and word breaks (#{name})" do
        laid = unquote(name) |> detected_glyphs() |> Enum.shuffle() |> Analysis.layout()

        text =
          laid
          |> Enum.zip(pangram_letters())
          |> Enum.chunk_by(fn {g, _} -> g.line end)
          |> Enum.map_join("\n", fn line ->
            Enum.map_join(line, fn {g, l} -> if g.space_before, do: " " <> l, else: l end)
          end)

        assert text == pangram_text()
        assert Enum.map(laid, & &1.position) == Enum.to_list(0..(length(laid) - 1))
      end
    end
  end

  describe "cluster/2" do
    for name <- ~w(pangram_clean pangram_photo) do
      test "groups identical symbols together, and only them (#{name})" do
        clustered = unquote(name) |> detected_glyphs() |> Analysis.analyze()

        groups =
          clustered
          |> Enum.zip(pangram_letters())
          |> Enum.group_by(fn {g, _} -> g.cluster end, fn {_, l} -> l end)

        # 26 letters in a pangram -> 26 symbols, each mapping to one letter.
        assert map_size(groups) == 26
        assert Enum.all?(groups, fn {_, letters} -> length(Enum.uniq(letters)) == 1 end)
      end
    end

    test "groups slightly different copies of the same symbol (resampled pixel art)" do
      clustered = "pixel_glyphs" |> detected_glyphs() |> Analysis.analyze()
      cluster_at = fn x, y -> Enum.find(clustered, &(&1.x == x and &1.y == y)).cluster end

      assert length(clustered) == 89
      assert clustered |> Enum.map(& &1.cluster) |> Enum.uniq() |> length() == 18

      # Copies in the first line are rendered 2px shorter than elsewhere.
      assert cluster_at.(222, 22) == cluster_at.(334, 150)
      assert cluster_at.(451, 22) == cluster_at.(292, 211)
      # Look-alikes that are different symbols (dotted vs hollow cross).
      refute cluster_at.(224, 150) == cluster_at.(251, 358)
    end

    test "compares sizes per picture" do
      clean = Enum.map(detected_glyphs("pangram_clean"), &Map.put(&1, :image_id, 1))
      # The same text photographed twice as large.
      zoomed =
        "pangram_photo"
        |> detected_glyphs()
        |> Enum.map(&%{&1 | x: &1.x * 2, y: &1.y * 2, w: &1.w * 2, h: &1.h * 2})
        |> Enum.map(&Map.put(&1, :image_id, 2))

      clusters = (clean ++ zoomed) |> Analysis.cluster() |> Enum.map(& &1.cluster)
      assert clusters |> Enum.uniq() |> length() == 26
      assert Enum.take(clusters, length(clean)) == Enum.drop(clusters, length(clean))
    end

    test "numbers clusters by first appearance" do
      clusters = detected_glyphs() |> Analysis.analyze() |> Enum.map(& &1.cluster)
      firsts = clusters |> Enum.uniq()
      assert firsts == Enum.to_list(0..(length(firsts) - 1))
    end

    test "a huge threshold groups everything, a tiny one nothing" do
      glyphs = detected_glyphs() |> Analysis.layout()

      assert glyphs |> Analysis.cluster(threshold: 10) |> Enum.map(& &1.cluster) |> Enum.uniq() ==
               [0]

      assert glyphs
             |> Analysis.cluster(threshold: 0.0)
             |> Enum.map(& &1.cluster)
             |> Enum.uniq()
             |> length() >
               26
    end

    test "empty input" do
      assert Analysis.analyze([]) == []
    end
  end

  describe "match/3" do
    # Existing glyphs of a puzzle: the clean pangram, one symbol per letter.
    defp existing do
      "pangram_clean"
      |> detected_glyphs()
      |> Analysis.layout()
      |> Enum.zip(pangram_letters())
      |> Enum.map(fn {g, letter} -> Map.merge(g, %{image_id: 1, symbol_id: letter}) end)
    end

    test "new glyphs join the existing symbols they match" do
      matched =
        "pangram_photo" |> detected_glyphs() |> Analysis.layout() |> Analysis.match(existing())

      assert Enum.map(matched, & &1.symbol_id) == pangram_letters()
      assert Enum.all?(matched, &is_nil(&1.cluster))
    end

    test "glyphs matching no existing symbol are grouped into new clusters" do
      matched =
        "pixel_glyphs" |> detected_glyphs() |> Analysis.layout() |> Analysis.match(existing())

      assert Enum.all?(matched, &is_nil(&1.symbol_id))
      assert matched |> Enum.map(& &1.cluster) |> Enum.uniq() |> length() == 18
    end

    test "existing symbols are never merged, even when they look alike" do
      # The user split "O" (★) in two symbols: new stars go to one of them.
      existing =
        Enum.map(existing(), fn
          %{symbol_id: "O", x: x} = g when x > 400 -> %{g | symbol_id: "O2"}
          g -> g
        end)

      matched =
        "pangram_photo" |> detected_glyphs() |> Analysis.layout() |> Analysis.match(existing)

      stars = for {g, "O"} <- Enum.zip(matched, pangram_letters()), do: g.symbol_id
      assert Enum.all?(stars, &(&1 in ["O", "O2"]))

      assert matched
             |> Enum.map(& &1.symbol_id)
             |> Enum.reject(&(&1 in ["O", "O2"]))
             |> Enum.uniq()
             |> length() == 25
    end

    test "a second picture of the same pixel-art cipher reuses its symbols" do
      existing =
        "pixel_glyphs"
        |> detected_glyphs()
        |> Analysis.analyze()
        |> Enum.map(&Map.merge(&1, %{image_id: 1, symbol_id: &1.cluster}))

      # The "two small squares" symbol of the first picture.
      pair = Enum.find(existing, &(&1.x == 137 and &1.y == 211)).symbol_id

      matched =
        "pixel_glyphs_2" |> detected_glyphs() |> Analysis.layout() |> Analysis.match(existing)

      assert Enum.count(matched, &(&1.symbol_id == pair)) == 3
      assert Enum.count(matched, & &1.symbol_id) == 29
      # Tapered bars, a half-filled square and the large emblem are new.
      new = for g <- matched, is_nil(g.symbol_id), do: {g.x, g.y}
      assert Enum.sort(new) == [{96, 49}, {220, 155}, {252, 88}]
    end

    test "no new glyphs" do
      assert Analysis.match([], existing()) == []
    end
  end
end
