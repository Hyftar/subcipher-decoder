defmodule SubcipherWeb.PictureUpload.UploadEntry do
  @moduledoc "A picture being uploaded: its preview with the symbols detected, progress, errors."
  use SubcipherWeb, :html

  import SubcipherWeb.PictureUpload.UploadErrors

  attr :entry, :any, required: true
  attr :upload, :any, required: true, doc: "the upload config"
  attr :detection, :map, required: true
  attr :target, :any, required: true

  def upload_entry(assigns) do
    ~H"""
    <div class="p-3 space-y-3">
      <div class="relative overflow-hidden rounded-xl bg-base-100">
        <.live_img_preview entry={@entry} class="block w-full h-auto" />
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
        <span class="truncate flex-1" title={@entry.client_name}>{@entry.client_name}</span>
        <progress
          :if={!@entry.done?}
          class="progress progress-primary w-24"
          value={@entry.progress}
          max="100"
        />
        <button
          type="button"
          phx-click="cancel-upload"
          phx-value-ref={@entry.ref}
          phx-target={@target}
          class="btn btn-ghost btn-sm"
          aria-label="Remove picture"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>
      <p :for={err <- upload_errors(@upload, @entry)} class="text-sm text-error">
        {error_to_string(err)}
      </p>
    </div>
    """
  end

  defp box_style(g, %{width: w, height: h}) do
    "left: #{g.x / w * 100}%; top: #{g.y / h * 100}%; " <>
      "width: #{g.w / w * 100}%; height: #{g.h / h * 100}%"
  end
end
