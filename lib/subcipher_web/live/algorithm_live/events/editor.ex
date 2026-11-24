defmodule SubcipherWeb.AlgorithmLive.Events.Editor do
  @moduledoc """
  Events changing an algorithm (owner only): visibility, title, steps, and
  deleting it.
  """
  use SubcipherWeb, :verified_routes

  import Phoenix.Component, only: [assign: 2, update: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]
  import Subcipher.Util, only: [wrap: 2]
  import SubcipherWeb.AlgorithmLive.Assigns, only: [reload: 2]

  alias Subcipher.Algorithms

  def handle_event("toggle_public", _params, socket) do
    algorithm = socket.assigns.algorithm
    {:ok, algorithm} = Algorithms.set_public(algorithm, !algorithm.public)

    socket
    |> assign(algorithm: algorithm)
    |> wrap(:noreply)
  end

  def handle_event("toggle_edit", _params, socket) do
    socket
    |> update(:editing, &(!&1))
    |> assign(step_forms: %{})
    |> wrap(:noreply)
  end

  def handle_event("rename", %{"title" => title}, socket) do
    case Algorithms.rename(socket.assigns.algorithm, title) do
      {:ok, algorithm} -> socket |> reload(algorithm) |> wrap(:noreply)
      {:error, _} -> wrap(socket, :noreply)
    end
  end

  def handle_event("add_step", %{"type" => type}, socket) do
    socket.assigns.algorithm
    |> Algorithms.add_step(type)
    |> after_edit(socket)
  end

  def handle_event("change_step_type", %{"index" => index, "type" => type}, socket) do
    socket.assigns.algorithm
    |> Algorithms.change_step_type(String.to_integer(index), type)
    |> after_edit(socket)
  end

  # Valid settings are saved; invalid ones stay in the form, with errors,
  # until fixed.
  def handle_event("update_step", %{"index" => index} = params, socket) do
    index = String.to_integer(index)

    case Algorithms.update_step_params(socket.assigns.algorithm, index, params["step"] || %{}) do
      {:ok, algorithm} ->
        socket
        |> update(:step_forms, &Map.delete(&1, index))
        |> reload(algorithm)
        |> wrap(:noreply)

      {:error, %Ecto.Changeset{} = changeset} ->
        form = to_form(changeset, as: :step, id: "algorithm-step-form-#{index}")

        socket
        |> update(:step_forms, &Map.put(&1, index, form))
        |> wrap(:noreply)

      {:error, _} ->
        wrap(socket, :noreply)
    end
  end

  def handle_event("move_step", %{"index" => index, "direction" => direction}, socket)
      when direction in ~w(up down) do
    socket.assigns.algorithm
    |> Algorithms.move_step(String.to_integer(index), String.to_existing_atom(direction))
    |> after_edit(socket)
  end

  def handle_event("delete_step", %{"index" => index}, socket) do
    socket.assigns.algorithm
    |> Algorithms.delete_step(String.to_integer(index))
    |> after_edit(socket)
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Algorithms.delete_algorithm(socket.assigns.algorithm)

    socket
    |> put_flash(:info, "Algorithm deleted.")
    |> push_navigate(to: ~p"/")
    |> wrap(:noreply)
  end

  # After a change of steps (indexes shift: forms being edited are dropped).
  defp after_edit({:ok, algorithm}, socket) do
    socket
    |> assign(step_forms: %{})
    |> reload(algorithm)
    |> wrap(:noreply)
  end

  defp after_edit({:error, :last_step}, socket) do
    socket
    |> put_flash(:error, "An algorithm needs at least one step.")
    |> wrap(:noreply)
  end

  defp after_edit({:error, _}, socket) do
    socket
    |> put_flash(:error, "This change isn't possible.")
    |> wrap(:noreply)
  end
end
