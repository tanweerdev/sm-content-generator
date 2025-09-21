defmodule SMG.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SMGWeb.Telemetry,
      SMG.Repo,
      {DNSCluster, query: Application.get_env(:cgenerator, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SMG.PubSub},
      # Start the Recall.ai bot status poller
      SMG.Services.RecallPoller,
      # Start the OAuth token refresher
      SMG.Services.OAuthTokenRefresher,
      # Start a worker by calling: SMG.Worker.start_link(arg)
      # {SMG.Worker, arg},
      # Start to serve requests, typically the last entry
      SMGWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SMG.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SMGWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
