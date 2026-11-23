defmodule Subcipher.StepsTest do
  use Subcipher.DataCase, async: true

  import Subcipher.CipherFixtures
  import Subcipher.AccountsFixtures, only: [user_scope_fixture: 0]
  alias Subcipher.{Ciphers, Steps}

  setup do
    %{puzzle: puzzle_fixture()}
  end

  test "add_step/2 appends a step with default parameters", %{puzzle: puzzle} do
    assert {:ok, caesar} = Steps.add_step(puzzle, "caesar")
    assert {:ok, keyword} = Steps.add_step(puzzle, "keyword_substitution")

    assert caesar.params == %{"shift" => 3}
    assert keyword.params == %{"keyword" => ""}
    assert Enum.map(Steps.list_steps(puzzle), & &1.id) == [caesar.id, keyword.id]
    assert Enum.map(Ciphers.get_puzzle!(puzzle.id).steps, & &1.id) == [caesar.id, keyword.id]

    assert {:error, :unknown_cipher} = Steps.add_step(puzzle, "enigma")
  end

  test "update_params/2 saves valid parameters only", %{puzzle: puzzle} do
    {:ok, step} = Steps.add_step(puzzle, "caesar")

    assert {:ok, step} = Steps.update_params(step, %{"shift" => "13"})
    assert step.params == %{"shift" => 13}
    assert Steps.params(step) == %{shift: 13}

    assert {:error, %Ecto.Changeset{action: :validate}} =
             Steps.update_params(step, %{"shift" => "99"})

    assert hd(Steps.list_steps(puzzle)).params == %{"shift" => 13}
  end

  test "update_params/2 keeps the parameters that aren't given", %{puzzle: puzzle} do
    {:ok, step} = Steps.add_step(puzzle, "anagram")
    {:ok, step} = Steps.update_params(step, %{"spaces" => "2"})
    {:ok, step} = Steps.update_params(step, %{"order" => "1,0"})
    assert step.params == %{"spaces" => 2, "order" => "1,0"}

    {:ok, step} = Steps.update_params(step, %{spaces: 0})
    assert step.params == %{"spaces" => 0, "order" => "1,0"}
  end

  test "run/2 chains steps, each decoding the previous output", %{puzzle: puzzle} do
    {:ok, caesar} = Steps.add_step(puzzle, "caesar")
    {:ok, caesar} = Steps.update_params(caesar, %{"shift" => "1"})
    {:ok, letters} = Steps.add_step(puzzle, "mixed_alphabet")
    {:ok, letters} = Steps.update_params(letters, %{"mapping" => %{"G" => "h", "D" => "i"}})

    assert [first, second] = Steps.run("Hej!", [caesar, letters])
    assert %{input: "Hej!", output: "Gdi!"} = first
    assert %{input: "Gdi!", output: "Hi·!"} = second
    assert Steps.run("unchanged", []) == []
  end

  test "move_step/2 and delete_step/1", %{puzzle: puzzle} do
    {:ok, a} = Steps.add_step(puzzle, "caesar")
    {:ok, b} = Steps.add_step(puzzle, "mixed_alphabet")
    {:ok, c} = Steps.add_step(puzzle, "keyword_substitution")

    assert {:ok, steps} = Steps.move_step(c, :up)
    assert Enum.map(steps, & &1.id) == [a.id, c.id, b.id]
    assert Enum.map(steps, & &1.position) == [1, 2, 3]

    # Already first: no change.
    assert {:ok, steps} = Steps.move_step(a, :up)
    assert Enum.map(steps, & &1.id) == [a.id, c.id, b.id]

    assert {:ok, _} = Steps.delete_step(c)
    assert Enum.map(Steps.list_steps(puzzle), & &1.id) == [a.id, b.id]

    # Adding after a deletion still appends.
    {:ok, d} = Steps.add_step(puzzle, "caesar")
    assert Enum.map(Steps.list_steps(puzzle), & &1.id) == [a.id, b.id, d.id]
  end

  test "steps are deleted with their puzzle", %{puzzle: puzzle} do
    {:ok, _} = Steps.add_step(puzzle, "caesar")
    {:ok, _} = Ciphers.delete_puzzle(puzzle)
    assert Repo.aggregate(Subcipher.Steps.Step, :count) == 0
  end

  describe "text puzzles" do
    test "create_text_puzzle/3 stores the text and a first step of any cipher" do
      scope = user_scope_fixture()

      assert {:ok, puzzle} =
               Ciphers.create_text_puzzle(scope, %{title: "Note", input_text: "Uryyb"}, "caesar")

      assert puzzle.input_kind == "text"
      assert [%{type: "caesar", position: 1}] = puzzle.steps
      assert Steps.source(puzzle) == "Uryyb"

      assert {:error, %Ecto.Changeset{}} =
               Ciphers.create_text_puzzle(scope, %{title: "Note", input_text: ""}, "caesar")

      assert {:error, :unknown_cipher} =
               Ciphers.create_text_puzzle(scope, %{title: "Note", input_text: "x"}, "enigma")

      # Nothing is left behind by failed creations.
      assert length(Ciphers.list_puzzles(scope)) == 1
    end

    test "keep at least one step" do
      {:ok, puzzle} =
        Ciphers.create_text_puzzle(
          user_scope_fixture(),
          %{title: "Note", input_text: "x"},
          "caesar"
        )

      [first] = puzzle.steps
      assert {:error, :last_step} = Steps.delete_step(first)

      {:ok, second} = Steps.add_step(puzzle, "keyword_substitution")
      assert {:ok, _} = Steps.delete_step(first)
      assert {:error, :last_step} = Steps.delete_step(second)
    end

    test "update_input_text/2" do
      {:ok, puzzle} =
        Ciphers.create_text_puzzle(
          user_scope_fixture(),
          %{title: "Note", input_text: "x"},
          "caesar"
        )

      assert {:ok, %{input_text: "Gur"}} = Ciphers.update_input_text(puzzle, "Gur")
    end
  end

  test "source/1 of a pictures puzzle is its deciphered symbols", %{puzzle: puzzle} do
    assert Steps.source(puzzle) == Ciphers.plaintext(puzzle)
    assert {:ok, _} = Steps.delete_step(elem(Steps.add_step(puzzle, "caesar"), 1))
  end

  test "change_type/2 resets the parameters", %{puzzle: puzzle} do
    {:ok, step} = Steps.add_step(puzzle, "caesar")
    {:ok, step} = Steps.update_params(step, %{"shift" => "7"})

    assert {:ok, step} = Steps.change_type(step, "symbol_substitution")
    assert %{type: "symbol_substitution", params: %{"mapping" => %{}}} = step
    assert {:error, :unknown_cipher} = Steps.change_type(step, "enigma")
  end
end
