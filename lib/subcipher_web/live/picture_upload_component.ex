defmodule SubcipherWeb.PictureUploadComponent do
  @moduledoc """
  Upload of a picture of cipher text. Symbols are detected in the browser
  (the `.GlyphDetector` hook of `SubcipherWeb.PictureUpload.Dropzone`) while the file uploads.

    * without a `puzzle`, submitting creates a new puzzle and navigates to it;
    * with a `puzzle`, the picture is added to it and the parent LiveView
      receives `{SubcipherWeb.PictureUploadComponent, {:added, puzzle, stats}}`.
  """
  use SubcipherWeb, :live_component

  alias Subcipher.Ciphers
  alias Subcipher.Ciphers.Analysis

  import SubcipherWeb.PictureUpload.{DetectionStatus, Dropzone, UploadErrors}

  @accept ~w(.png .jpg .jpeg .webp .gif .bmp)
  @max_size 15_000_000

  @impl true
  def mount(socket) do
    socket
    |> assign(form: to_form(%{"title" => ""}, as: :picture), detection: idle())
    |> allow_upload(:image,
      accept: @accept,
      max_entries: 1,
      max_file_size: @max_size,
      auto_upload: true
    )
    |> wrap(:ok)
  end

  @impl true
  def update(assigns, socket) do
    socket |> assign(puzzle: nil, scope: nil) |> assign(assigns) |> wrap(:ok)
  end

  defp idle, do: %{status: :idle, glyphs: [], width: nil, height: nil, message: nil}

  @impl true
  def handle_event("validate", %{"picture" => params}, socket) do
    socket |> assign(form: to_form(params, as: :picture)) |> wrap(:noreply)
  end

  def handle_event("validate", _params, socket), do: wrap(socket, :noreply)

  def handle_event("detecting", _params, socket) do
    socket |> assign(detection: %{idle() | status: :detecting}) |> wrap(:noreply)
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

    socket |> assign(detection: detection) |> wrap(:noreply)
  end

  def handle_event("detected", _payload, socket) do
    assign(socket, detection: %{idle() | status: :error, message: "Invalid picture."})
    |> wrap(:noreply)
  end

  def handle_event("detection_failed", %{"message" => message}, socket) do
    socket |> assign(detection: %{idle() | status: :error, message: message}) |> wrap(:noreply)
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    socket |> cancel_upload(:image, ref) |> assign(detection: idle()) |> wrap(:noreply)
  end

  def handle_event("save", params, socket) do
    %{detection: detection} = socket.assigns

    cond do
      detection.status != :ready ->
        socket |> put_flash(:error, "Wait for the symbol detection to finish.") |> wrap(:noreply)

      not upload_done?(socket.assigns.uploads.image) ->
        socket |> put_flash(:error, "The picture is still uploading.") |> wrap(:noreply)

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

        socket.assigns.puzzle
        |> persist(socket.assigns.scope, image, entry, params, detection.glyphs)
        |> wrap(:ok)
      end)

    socket = assign(socket, detection: idle())

    case result do
      {:ok, puzzle} ->
        socket |> push_navigate(to: ~p"/puzzles/#{puzzle}") |> wrap(:noreply)

      {:ok, puzzle, stats} ->
        send(self(), {__MODULE__, {:added, puzzle, stats}})
        wrap(socket, :noreply)

      {:error, %Ecto.Changeset{} = changeset} ->
        socket
        |> assign(form: to_form(changeset, as: :picture))
        |> put_flash(:error, "Could not create the puzzle, please upload the picture again.")
        |> wrap(:noreply)

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Could not save the picture, please try again.")
        |> wrap(:noreply)
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
        <.dropzone
          id={"#{@id}-dropzone"}
          upload={@uploads.image}
          detection={@detection}
          target={@myself}
          compact={@puzzle != nil}
        />

        <p :for={err <- upload_errors(@uploads.image)} class="text-sm text-error">
          {error_to_string(err)}
        </p>

        <.detection_status id={"#{@id}-status"} detection={@detection} />

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
end
