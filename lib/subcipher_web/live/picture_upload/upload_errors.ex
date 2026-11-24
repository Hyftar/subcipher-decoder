defmodule SubcipherWeb.PictureUpload.UploadErrors do
  @moduledoc "Upload errors, as messages."

  @doc "The message of an upload error."

  def error_to_string(:too_large), do: "This picture is too large (max 15 MB)."

  def error_to_string(:not_accepted),
    do: "Unsupported file type. Use PNG, JPEG, WebP, GIF or BMP."

  def error_to_string(:too_many_files), do: "Only one picture at a time."
  def error_to_string(_), do: "Upload failed."
end
