defmodule SMG.Integrations.LinkedInAuth do
  @moduledoc """
  LinkedIn OAuth 2.0 authentication and token refresh functionality
  """

  use Tesla
  require Logger

  plug Tesla.Middleware.BaseUrl, "https://www.linkedin.com"
  plug Tesla.Middleware.Headers, [{"Content-Type", "application/x-www-form-urlencoded"}]
  plug Tesla.Middleware.JSON

  @doc """
  Refreshes a LinkedIn OAuth access token using the refresh token
  """
  def refresh_token(refresh_token) do
    Logger.info("Attempting to refresh LinkedIn OAuth token")

    body = %{
      grant_type: "refresh_token",
      refresh_token: refresh_token,
      client_id: linkedin_client_id(),
      client_secret: linkedin_client_secret()
    }

    case post("/oauth/v2/accessToken", body) do
      {:ok, %{status: 200, body: response}} ->
        Logger.info("Successfully refreshed LinkedIn OAuth token")
        {:ok, response}

      {:ok, %{status: status, body: error}} ->
        Logger.error("Failed to refresh LinkedIn OAuth token",
          status: status,
          error: error
        )

        {:error, "Failed to refresh token: #{status} - #{inspect(error)}"}

      {:error, reason} ->
        Logger.error("LinkedIn OAuth token refresh API request failed", reason: reason)
        {:error, "API request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Validates a LinkedIn access token by making a test API call
  """
  def validate_token(access_token) do
    headers = [{"Authorization", "Bearer #{access_token}"}]

    case Tesla.get("https://api.linkedin.com/v2/userinfo", headers: headers) do
      {:ok, %{status: 200}} ->
        {:ok, :valid}

      {:ok, %{status: 401}} ->
        {:error, :invalid}

      {:ok, %{status: status}} ->
        {:error, "Unexpected status: #{status}"}

      {:error, reason} ->
        {:error, "API request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Gets LinkedIn user profile information
  """
  def get_user_profile(access_token) do
    headers = [{"Authorization", "Bearer #{access_token}"}]

    case Tesla.get("https://api.linkedin.com/v2/userinfo", headers: headers) do
      {:ok, %{status: 200, body: profile}} ->
        user_data = %{
          platform_user_id: profile["sub"],
          email: profile["email"],
          name: profile["name"],
          picture: profile["picture"]
        }

        {:ok, user_data}

      {:ok, %{status: status, body: error}} ->
        Logger.error("Failed to get LinkedIn user profile",
          status: status,
          error: error
        )

        {:error, "Failed to get profile: #{status} - #{inspect(error)}"}

      {:error, reason} ->
        Logger.error("LinkedIn profile API request failed", reason: reason)
        {:error, "API request failed: #{inspect(reason)}"}
    end
  end

  defp linkedin_client_id do
    System.get_env("LINKEDIN_CLIENT_ID") ||
      raise "LINKEDIN_CLIENT_ID environment variable not set"
  end

  defp linkedin_client_secret do
    System.get_env("LINKEDIN_CLIENT_SECRET") ||
      raise "LINKEDIN_CLIENT_SECRET environment variable not set"
  end
end
