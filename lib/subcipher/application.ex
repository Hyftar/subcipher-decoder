defmodule Subcipher.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SubcipherWeb.Telemetry,
      Subcipher.Repo,
      {DNSCluster, query: Application.get_env(:subcipher, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Subcipher.PubSub},
      # Slots for the CPU-heavy deep pass of the cipher guesser.
      Subcipher.Guesser.Limiter,
      # Start a worker by calling: Subcipher.Worker.start_link(arg)
      # {Subcipher.Worker, arg},
      # Start to serve requests, typically the last entry
      SubcipherWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Subcipher.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SubcipherWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
