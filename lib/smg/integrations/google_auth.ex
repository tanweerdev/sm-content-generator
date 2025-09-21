defmodule SMG.Integrations.GoogleAuth do
  @moduledoc """
  Google OAuth 2.0 authentication and token refresh functionality
  """

  use Tesla
  require Logger

  plug Tesla.Middleware.BaseUrl, "https://oauth2.googleapis.com"
  plug Tesla.Middleware.Headers, [{"Content-Type", "application/x-www-form-urlencoded"}]
  plug Tesla.Middleware.JSON

  @doc """
  Refreshes a Google OAuth access token using the refresh token
  """
  def refresh_token(refresh_token) do
    Logger.info("Attempting to refresh Google OAuth token")

    body = %{
      client_id: google_client_id(),
      client_secret: google_client_secret(),
      refresh_token: refresh_token,
      grant_type: "refresh_token"
    }

    case post("/token", body) do
      {:ok, %{status: 200, body: response}} ->
        Logger.info("Successfully refreshed Google OAuth token")
        {:ok, response}

      {:ok, %{status: status, body: error}} ->
        Logger.error("Failed to refresh Google OAuth token",
          status: status,
          error: error
        )

        {:error, "Failed to refresh token: #{status} - #{inspect(error)}"}

      {:error, reason} ->
        Logger.error("Google OAuth token refresh API request failed", reason: reason)
        {:error, "API request failed: #{inspect(reason)}"}
    end
  end

  defp google_client_id do
    System.get_env("GOOGLE_CLIENT_ID") ||
      raise "GOOGLE_CLIENT_ID environment variable not set"
  end

  defp google_client_secret do
    System.get_env("GOOGLE_CLIENT_SECRET") ||
      raise "GOOGLE_CLIENT_SECRET environment variable not set"
  end
end
