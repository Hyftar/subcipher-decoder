defmodule SubcipherWeb.PuzzleLive.Events.Step do
  @moduledoc """
  Events of the decoding steps of a puzzle: adding, changing, ordering and
  removing them, and the input text of a text puzzle.
  """
  import Phoenix.Component, only: [update: 3]
  import Subcipher.Util, only: [wrap: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_patch: 2]

  alias Subcipher.{Ciphers, Steps}

  import SubcipherWeb.PuzzleLive.Assigns,
    only: [
      assign_pipeline: 1,
      find_step: 2,
      reload: 1,
      step_number: 2,
      step_path: 2,
      to_step_form: 2
    ]

  def handle_event("add_step", %{"type" => type}, socket) do
    case Steps.add_step(socket.assigns.puzzle, type) do
      {:ok, step} ->
        socket = reload(socket)

        socket
        |> push_patch(to: step_path(socket, step_number(socket, step.id)))
        |> wrap(:noreply)

      {:error, _} ->
        socket |> put_flash(:error, "Could not add this step.") |> wrap(:noreply)
    end
  end

  def handle_event("change_step_type", %{"step_id" => id, "type" => type}, socket) do
    with %{} = step <- find_step(socket, id),
         {:ok, _} <- Steps.change_type(step, type) do
      socket
      |> update(:step_forms, &Map.delete(&1, step.id))
      |> reload()
      |> wrap(:noreply)
    else
      _ ->
        socket |> put_flash(:error, "Could not change the cipher of this step.") |> wrap(:noreply)
    end
  end

  def handle_event("update_input", %{"puzzle" => %{"input_text" => text}}, socket) do
    case Ciphers.update_input_text(socket.assigns.puzzle, text) do
      {:ok, _} -> socket |> reload() |> wrap(:noreply)
      {:error, _} -> socket |> put_flash(:error, "This text is too long.") |> wrap(:noreply)
    end
  end

  def handle_event("update_step", %{"step_id" => id} = params, socket) do
    case find_step(socket, id) do
      nil -> wrap(socket, :noreply)
      step -> socket |> update_step(step, Map.get(params, "step", %{})) |> wrap(:noreply)
    end
  end

  def handle_event("apply_suggestion", %{"id" => id, "params" => params}, socket) do
    case find_step(socket, id) do
      nil -> wrap(socket, :noreply)
      step -> socket |> update_step(step, params) |> wrap(:noreply)
    end
  end

  def handle_event("delete_step", %{"id" => id}, socket) do
    case find_step(socket, id) do
      nil ->
        wrap(socket, :noreply)

      step ->
        number = step_number(socket, step.id)

        case Steps.delete_step(step) do
          {:ok, _} ->
            socket = socket |> update(:step_forms, &Map.delete(&1, step.id)) |> reload()
            socket |> push_patch(to: step_path(socket, max(number - 1, 1))) |> wrap(:noreply)

          {:error, :last_step} ->
            socket
            |> put_flash(:error, "A text cipher needs at least one step.")
            |> wrap(:noreply)
        end
    end
  end

  def handle_event("move_step", %{"id" => id, "direction" => direction}, socket)
      when direction in ~w(up down) do
    case find_step(socket, id) do
      nil ->
        wrap(socket, :noreply)

      step ->
        {:ok, _} = Steps.move_step(step, String.to_existing_atom(direction))
        socket = reload(socket)

        socket
        |> push_patch(to: step_path(socket, step_number(socket, step.id)))
        |> wrap(:noreply)
    end
  end

  @doc """
  Valid parameters are saved; invalid ones stay in the form, with errors,
  until fixed (the step keeps decoding with its last valid parameters).
  """
  def update_step(socket, step, params) do
    case Steps.update_params(step, params) do
      {:ok, _step} ->
        socket |> update(:step_forms, &Map.delete(&1, step.id)) |> reload()

      {:error, changeset} ->
        socket
        |> update(:step_forms, &Map.put(&1, step.id, to_step_form(changeset, step)))
        |> assign_pipeline()
    end
  end
end
