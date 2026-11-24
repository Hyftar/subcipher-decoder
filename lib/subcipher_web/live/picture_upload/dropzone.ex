defmodule SubcipherWeb.PictureUpload.Dropzone do
  @moduledoc """
  Where a picture is dropped, pasted or picked. The `.GlyphDetector` hook
  detects its symbols in the browser while it uploads, and sends them to
  the target ("detecting", "detected", "detection_failed").
  """
  use SubcipherWeb, :html

  import SubcipherWeb.PictureUpload.UploadEntry

  attr :id, :string, required: true
  attr :upload, :any, required: true, doc: "the upload config (@uploads.image)"
  attr :detection, :map, required: true, doc: "status, glyphs, width, height, message"
  attr :target, :any, required: true, doc: "the LiveComponent handling the events"
  attr :compact, :boolean, default: false, doc: "less padding (adding to a puzzle)"

  def dropzone(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook=".GlyphDetector"
      phx-target={@target}
      data-upload="image"
      phx-drop-target={@upload.ref}
      class={[
        "relative rounded-2xl border-2 border-dashed transition-colors",
        "border-base-300 hover:border-primary/60 bg-base-200/40",
        "phx-drop-target-active:border-primary phx-drop-target-active:bg-primary/5"
      ]}
    >
      <label
        :if={@upload.entries == []}
        for={@upload.ref}
        class={[
          "flex flex-col items-center justify-center gap-3 cursor-pointer text-center",
          if(@compact, do: "py-8", else: "py-16")
        ]}
      >
        <span class="grid place-items-center size-14 rounded-full bg-primary/10 text-primary">
          <.icon name="hero-photo" class="size-7" />
        </span>
        <span class="font-medium">Drop a picture here, paste it, or click to browse</span>
        <span class="text-sm text-base-content/60">PNG, JPEG, WebP, GIF or BMP · 15 MB max</span>
      </label>
      <.live_file_input upload={@upload} class="sr-only" />

      <.upload_entry
        :for={entry <- @upload.entries}
        entry={entry}
        upload={@upload}
        detection={@detection}
        target={@target}
      />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".GlyphDetector">
        import { detectGlyphs, toGrayscale } from "@/js/glyph_detector"

        // Larger pictures are downscaled before analysis: plenty for symbol
        // detection and keeps the browser responsive.
        const MAX_SIDE = 2000

        // Mounted on the element wrapping the upload <input>. Whenever a picture is
        // chosen (file picker, drag & drop or paste), symbols are detected in the
        // browser and sent as a "detected" event to the LiveView, or to the
        // LiveComponent the element belongs to.
        export default {
          mounted() {
            this.run = 0
            this.onInput = (e) => {
              const input = e.target
              if (input?.type === "file" && input.files?.[0]) this.detect(input.files[0])
            }
            this.onPaste = (e) => {
              const file = [...(e.clipboardData?.files || [])].find((f) => f.type.startsWith("image/"))
              if (!file) return
              e.preventDefault()
              this.upload(this.el.dataset.upload, [file])
              // Files added with upload() aren't exposed through input.files, so the
              // "input" listener below can't see them: detect directly.
              this.detect(file)
            }
            this.el.addEventListener("input", this.onInput)
            window.addEventListener("paste", this.onPaste)
          },

          destroyed() {
            window.removeEventListener("paste", this.onPaste)
          },

          async detect(file) {
            const run = ++this.run
            this.pushEventTo(this.el, "detecting", {})
            // Let the "detecting" state render before blocking the main thread.
            await new Promise((resolve) => setTimeout(resolve, 30))

            try {
              const bitmap = await createImageBitmap(file)
              const scale = Math.min(1, MAX_SIDE / Math.max(bitmap.width, bitmap.height))
              const width = Math.max(1, Math.round(bitmap.width * scale))
              const height = Math.max(1, Math.round(bitmap.height * scale))

              const canvas = document.createElement("canvas")
              canvas.width = width
              canvas.height = height
              const ctx = canvas.getContext("2d", { willReadFrequently: true })
              ctx.drawImage(bitmap, 0, 0, width, height)
              const { data } = ctx.getImageData(0, 0, width, height)

              const glyphs = detectGlyphs(toGrayscale(data, width, height), width, height).map((g) => {
                // Back to the coordinates of the original picture.
                const x = Math.floor(g.x / scale)
                const y = Math.floor(g.y / scale)
                return {
                  x,
                  y,
                  w: Math.min(bitmap.width - x, Math.ceil(g.w / scale)),
                  h: Math.min(bitmap.height - y, Math.ceil(g.h / scale)),
                  f: g.f,
                }
              })

              if (run !== this.run) return // a newer picture was chosen meanwhile
              this.pushEventTo(this.el, "detected", { width: bitmap.width, height: bitmap.height, glyphs })
              bitmap.close()
            } catch (err) {
              if (run !== this.run) return
              console.error(err)
              this.pushEventTo(this.el, "detection_failed", { message: "This picture could not be read." })
            }
          },
        }
      </script>
    </div>
    """
  end
end
