defmodule SubcipherWeb.PuzzleLive.Index do
  use SubcipherWeb, :live_view

  alias Subcipher.Ciphers
  alias Subcipher.Ciphers.Analysis

  @accept ~w(.png .jpg .jpeg .webp .gif .bmp)
  @max_size 15_000_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Puzzles")
     |> assign(:form, to_form(%{"title" => ""}, as: :puzzle))
     |> assign(:detection, idle())
     |> assign(:puzzles, Ciphers.list_puzzles())
     |> allow_upload(:image,
       accept: @accept,
       max_entries: 1,
       max_file_size: @max_size,
       auto_upload: true
     )}
  end

  defp idle, do: %{status: :idle, glyphs: [], width: nil, height: nil, message: nil}

  @impl true
  def handle_event("validate", %{"puzzle" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :puzzle))}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("detecting", _params, socket) do
    {:noreply, assign(socket, :detection, %{idle() | status: :detecting})}
  end

  def handle_event("detected", %{"width" => w, "height" => h} = payload, socket)
      when is_integer(w) and is_integer(h) and w > 0 and h > 0 do
    detection =
      case Analysis.parse_detection(payload) do
        {:ok, glyphs} ->
          %{status: :ready, glyphs: glyphs, width: w, height: h, message: nil}

        {:error, :no_glyphs} ->
          %{idle() | status: :error, message: "No symbols were found in this picture."}

        {:error, _} ->
          %{idle() | status: :error, message: "The detection result was invalid."}
      end

    {:noreply, assign(socket, :detection, detection)}
  end

  def handle_event("detected", _payload, socket) do
    {:noreply,
     assign(socket, :detection, %{idle() | status: :error, message: "Invalid picture."})}
  end

  def handle_event("detection_failed", %{"message" => message}, socket) do
    {:noreply, assign(socket, :detection, %{idle() | status: :error, message: message})}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, socket |> cancel_upload(:image, ref) |> assign(:detection, idle())}
  end

  def handle_event("save", %{"puzzle" => params}, socket) do
    %{detection: detection} = socket.assigns

    cond do
      detection.status != :ready ->
        {:noreply, put_flash(socket, :error, "Wait for the symbol detection to finish.")}

      not upload_done?(socket.assigns.uploads.image) ->
        {:noreply, put_flash(socket, :error, "The picture is still uploading.")}

      true ->
        create(socket, params, detection)
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    puzzle = Ciphers.get_puzzle!(id)
    {:ok, _} = Ciphers.delete_puzzle(puzzle)

    {:noreply,
     socket
     |> put_flash(:info, "Puzzle deleted.")
     |> assign(:puzzles, Ciphers.list_puzzles())}
  end

  defp create(socket, params, detection) do
    [result] =
      consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        title =
          case String.trim(params["title"] || "") do
            "" -> Path.rootname(entry.client_name)
            title -> title
          end

        image = %{
          path: path,
          ext: entry.client_name |> Path.extname() |> String.downcase(),
          width: detection.width,
          height: detection.height
        }

        {:ok, Ciphers.create_puzzle(%{title: title}, image, detection.glyphs)}
      end)

    case result do
      {:ok, puzzle} ->
        {:noreply, push_navigate(socket, to: ~p"/puzzles/#{puzzle}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:detection, idle())
         |> assign(:form, to_form(changeset, as: :puzzle))
         |> put_flash(:error, "Could not create the puzzle, please upload the picture again.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:detection, idle())
         |> put_flash(:error, "Could not save the picture, please try again.")}
    end
  end

  defp upload_done?(%{entries: [entry]}), do: entry.done? and entry.valid?
  defp upload_done?(_), do: false

  defp error_to_string(:too_large), do: "This picture is too large (max 15 MB)."

  defp error_to_string(:not_accepted),
    do: "Unsupported file type. Use PNG, JPEG, WebP, GIF or BMP."

  defp error_to_string(:too_many_files), do: "Only one picture at a time."
  defp error_to_string(_), do: "Upload failed."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="grid gap-8 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
        <div class="space-y-4">
          <div>
            <h1 class="text-2xl font-bold tracking-tight">Crack a substitution cipher</h1>
            <p class="text-base-content/70 mt-1">
              Upload a picture of the cipher text. Every symbol is detected and identical
              symbols are grouped, so you can substitute them with letters until the message
              appears.
            </p>
          </div>

          <.form
            for={@form}
            id="upload-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-4"
          >
            <div
              id="dropzone"
              phx-hook="GlyphDetector"
              data-upload="image"
              phx-drop-target={@uploads.image.ref}
              class={[
                "relative rounded-2xl border-2 border-dashed transition-colors",
                "border-base-300 hover:border-primary/60 bg-base-200/40",
                "phx-drop-target-active:border-primary phx-drop-target-active:bg-primary/5"
              ]}
            >
              <label
                :if={@uploads.image.entries == []}
                for={@uploads.image.ref}
                class="flex flex-col items-center justify-center gap-3 py-16 cursor-pointer text-center"
              >
                <span class="grid place-items-center size-14 rounded-full bg-primary/10 text-primary">
                  <.icon name="hero-photo" class="size-7" />
                </span>
                <span class="font-medium">Drop a picture here, paste it, or click to browse</span>
                <span class="text-sm text-base-content/60">PNG, JPEG, WebP, GIF or BMP · 15 MB max</span>
              </label>
              <.live_file_input upload={@uploads.image} class="sr-only" />

              <div :for={entry <- @uploads.image.entries} class="p-3 space-y-3">
                <div class="relative overflow-hidden rounded-xl bg-base-100">
                  <.live_img_preview entry={entry} class="block w-full h-auto" />
                  <div :if={@detection.status == :ready} class="absolute inset-0">
                    <span
                      :for={g <- @detection.glyphs}
                      class="absolute ring-1 ring-primary/80 bg-primary/10 rounded-[2px]"
                      style={box_style(g, @detection)}
                    />
                  </div>
                  <div
                    :if={@detection.status == :detecting}
                    class="absolute inset-0 grid place-items-center bg-base-100/60 backdrop-blur-[1px]"
                  >
                    <span class="loading loading-spinner loading-lg text-primary"></span>
                  </div>
                </div>

                <div class="flex items-center gap-3 text-sm">
                  <span class="truncate flex-1" title={entry.client_name}>{entry.client_name}</span>
                  <progress
                    :if={!entry.done?}
                    class="progress progress-primary w-24"
                    value={entry.progress}
                    max="100"
                  />
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-value-ref={entry.ref}
                    class="btn btn-ghost btn-xs"
                    aria-label="Remove picture"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
                <p
                  :for={err <- upload_errors(@uploads.image, entry)}
                  class="text-sm text-error"
                >
                  {error_to_string(err)}
                </p>
              </div>
            </div>

            <p :for={err <- upload_errors(@uploads.image)} class="text-sm text-error">
              {error_to_string(err)}
            </p>

            <div id="detection-status" class="text-sm min-h-5">
              <span :if={@detection.status == :detecting} class="text-base-content/70">
                Detecting symbols…
              </span>
              <span :if={@detection.status == :ready} class="text-success">
                <.icon name="hero-check-circle" class="size-4 align-text-bottom" />
                {length(@detection.glyphs)} symbols detected.
              </span>
              <span :if={@detection.status == :error} class="text-error">
                {@detection.message}
              </span>
            </div>

            <div class="flex flex-col sm:flex-row gap-3 sm:items-end">
              <div class="flex-1">
                <.input field={@form[:title]} label="Title (optional)" placeholder="Zodiac 340" />
              </div>
              <.button
                variant="primary"
                class="btn btn-primary mb-2"
                disabled={@detection.status != :ready}
                phx-disable-with="Creating…"
              >
                Start decoding <.icon name="hero-arrow-right" class="size-4" />
              </.button>
            </div>
          </.form>
        </div>

        <aside class="space-y-3">
          <h2 class="font-semibold text-base-content/80">Your puzzles</h2>
          <p :if={@puzzles == []} class="text-sm text-base-content/60">
            No puzzles yet. Upload a picture to get started.
          </p>
          <ul id="puzzles" class="space-y-2">
            <li
              :for={%{puzzle: p} = row <- @puzzles}
              id={"puzzle-#{p.id}"}
              class="group flex items-center gap-3 rounded-xl border border-base-300 bg-base-100 p-2 pr-3 transition hover:border-primary/50 hover:shadow-sm"
            >
              <.link navigate={~p"/puzzles/#{p}"} class="flex flex-1 items-center gap-3 min-w-0">
                <img
                  src={p.image_path}
                  alt=""
                  class="size-14 rounded-lg object-cover bg-base-200 shrink-0"
                />
                <div class="min-w-0 flex-1">
                  <p class="font-medium truncate">{p.title}</p>
                  <p class="text-xs text-base-content/60">
                    {row.glyph_count} glyphs · {row.symbol_count} symbols
                  </p>
                  <div class="mt-1 h-1.5 rounded-full bg-base-200 overflow-hidden">
                    <div
                      class="h-full bg-primary transition-all"
                      style={"width: #{percent(row.solved_count, row.symbol_count)}%"}
                    />
                  </div>
                </div>
              </.link>
              <button
                type="button"
                phx-click="delete"
                phx-value-id={p.id}
                data-confirm={"Delete “#{p.title}”?"}
                class="btn btn-ghost btn-sm btn-square opacity-0 group-hover:opacity-100 focus:opacity-100"
                aria-label={"Delete #{p.title}"}
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </li>
          </ul>
        </aside>
      </section>
    </Layouts.app>
    """
  end

  defp box_style(g, %{width: w, height: h}) do
    "left: #{g.x / w * 100}%; top: #{g.y / h * 100}%; " <>
      "width: #{g.w / w * 100}%; height: #{g.h / h * 100}%"
  end

  defp percent(_, 0), do: 0
  defp percent(n, total), do: round(n / total * 100)
end
