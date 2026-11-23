defmodule SubcipherWeb.Plugs.HealthCheck do
  @moduledoc """
  Answers `GET /health` before the rest of the endpoint (no session, no
  logging): 200 when the app can reach the database, 503 otherwise.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "GET", path_info: ["health"]} = conn, _opts) do
    {status, body} =
      case Ecto.Adapters.SQL.query(Subcipher.Repo, "SELECT 1", [], timeout: 2_000) do
        {:ok, _} -> {200, "ok"}
        {:error, _} -> {503, "database unavailable"}
      end

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
    |> halt()
  end

  def call(conn, _opts), do: conn
end
