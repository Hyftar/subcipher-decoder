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
end
