defmodule SubcipherWeb.PictureUploadComponent do
  @moduledoc """
  Upload of a picture of cipher text. Symbols are detected in the browser
  (`GlyphDetector` hook) while the file uploads.

    * without a `puzzle`, submitting creates a new puzzle and navigates to it;
    * with a `puzzle`, the picture is added to it and the parent LiveView
      receives `{SubcipherWeb.PictureUploadComponent, {:added, puzzle, stats}}`.
  """
  use SubcipherWeb, :live_component

  alias Subcipher.Ciphers
  alias Subcipher.Ciphers.Analysis

  @accept ~w(.png .jpg .jpeg .webp .gif .bmp)
  @max_size 15_000_000

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:form, to_form(%{"title" => ""}, as: :picture))
     |> assign(:detection, idle())
     |> allow_upload(:image,
       accept: @accept,
       max_entries: 1,
       max_file_size: @max_size,
       auto_upload: true
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(:puzzle, nil) |> assign(:scope, nil) |> assign(assigns)}
  end

  defp idle, do: %{status: :idle, glyphs: [], width: nil, height: nil, message: nil}

  @impl true
  def handle_event("validate", %{"picture" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :picture))}
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

  def handle_event("save", params, socket) do
    %{detection: detection} = socket.assigns

    cond do
      detection.status != :ready ->
        {:noreply, put_flash(socket, :error, "Wait for the symbol detection to finish.")}

      not upload_done?(socket.assigns.uploads.image) ->
        {:noreply, put_flash(socket, :error, "The picture is still uploading.")}

      true ->
        save(socket, Map.get(params, "picture", %{}), detection)
    end
  end

  defp save(socket, params, detection) do
    [result] =
      consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        image = %{
          path: path,
          ext: entry.client_name |> Path.extname() |> String.downcase(),
          width: detection.width,
          height: detection.height
        }

        {:ok,
         persist(
           socket.assigns.puzzle,
           socket.assigns.scope,
           image,
           entry,
           params,
           detection.glyphs
         )}
      end)

    socket = assign(socket, :detection, idle())

    case result do
      {:ok, puzzle} ->
        {:noreply, push_navigate(socket, to: ~p"/puzzles/#{puzzle}")}

      {:ok, puzzle, stats} ->
        send(self(), {__MODULE__, {:added, puzzle, stats}})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: :picture))
         |> put_flash(:error, "Could not create the puzzle, please upload the picture again.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not save the picture, please try again.")}
    end
  end

  defp persist(nil, scope, image, entry, params, glyphs) do
    title =
      case String.trim(params["title"] || "") do
        "" -> Path.rootname(entry.client_name)
        title -> title
      end

    Ciphers.create_puzzle(scope, %{title: title}, image, glyphs)
  end

  defp persist(puzzle, scope, image, _entry, _params, glyphs) do
    if Subcipher.Accounts.Scope.owner?(scope, puzzle),
      do: Ciphers.add_image(puzzle, image, glyphs),
      else: {:error, :forbidden}
  end

  defp upload_done?(%{entries: [entry]}), do: entry.done? and entry.valid?
  defp upload_done?(_), do: false

  # Uploads finish in the background (LiveView waits for them on submit), so
  # only the detection result and the validity of the picture matter here.
  defp ready_to_submit?(detection, %{entries: [entry]} = upload),
    do: detection.status == :ready and entry.valid? and upload_errors(upload) == []

  defp ready_to_submit?(_detection, _upload), do: false

  defp error_to_string(:too_large), do: "This picture is too large (max 15 MB)."

  defp error_to_string(:not_accepted),
    do: "Unsupported file type. Use PNG, JPEG, WebP, GIF or BMP."

  defp error_to_string(:too_many_files), do: "Only one picture at a time."
  defp error_to_string(_), do: "Upload failed."

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        id={"#{@id}-form"}
        phx-change="validate"
        phx-submit="save"
        phx-target={@myself}
        class="space-y-4"
      >
        <div
          id={"#{@id}-dropzone"}
          phx-hook="GlyphDetector"
          phx-target={@myself}
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
            class={[
              "flex flex-col items-center justify-center gap-3 cursor-pointer text-center",
              if(@puzzle, do: "py-8", else: "py-16")
            ]}
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
                phx-target={@myself}
                class="btn btn-ghost btn-xs"
                aria-label="Remove picture"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
            <p :for={err <- upload_errors(@uploads.image, entry)} class="text-sm text-error">
              {error_to_string(err)}
            </p>
          </div>
        </div>

        <p :for={err <- upload_errors(@uploads.image)} class="text-sm text-error">
          {error_to_string(err)}
        </p>

        <div id={"#{@id}-status"} class="text-sm min-h-5">
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

        <div class="flex flex-col sm:flex-row gap-3 sm:items-end sm:justify-end">
          <div :if={!@puzzle} class="flex-1">
            <.input field={@form[:title]} label="Title (optional)" placeholder="Zodiac 340" />
          </div>
          <.button
            variant="primary"
            class={["btn btn-primary", !@puzzle && "mb-2"]}
            disabled={not ready_to_submit?(@detection, @uploads.image)}
            phx-disable-with={if @puzzle, do: "Adding…", else: "Creating…"}
          >
            <%= if @puzzle do %>
              <.icon name="hero-plus" class="size-4" /> Add to this cipher
            <% else %>
              Start decoding <.icon name="hero-arrow-right" class="size-4" />
            <% end %>
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  defp box_style(g, %{width: w, height: h}) do
    "left: #{g.x / w * 100}%; top: #{g.y / h * 100}%; " <>
      "width: #{g.w / w * 100}%; height: #{g.h / h * 100}%"
  end
end
