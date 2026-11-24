defmodule Subcipher.Guesser.LimiterTest do
  use ExUnit.Case, async: true

  alias Subcipher.Guesser.Limiter

  setup do
    limiter =
      start_supervised!({Limiter, name: :"limiter_#{System.unique_integer([:positive])}", max: 1})

    %{limiter: limiter}
  end

  test "runs while a slot is free", %{limiter: limiter} do
    assert Limiter.run(fn -> :done end, limiter) == {:ok, :done}
    assert Limiter.run(fn -> :again end, limiter) == {:ok, :again}
  end

  test "turns runs away when every slot is taken, frees it when the holder dies", %{
    limiter: limiter
  } do
    test = self()

    holder =
      spawn(fn ->
        Limiter.run(fn -> send(test, :holding) && receive(do: (:never -> :ok)) end, limiter)
      end)

    assert_receive :holding
    assert Limiter.run(fn -> :nope end, limiter) == {:error, :busy}

    ref = Process.monitor(holder)
    Process.exit(holder, :kill)
    assert_receive {:DOWN, ^ref, :process, ^holder, :killed}
    _ = :sys.get_state(limiter)

    assert Limiter.run(fn -> :free end, limiter) == {:ok, :free}
  end
end
