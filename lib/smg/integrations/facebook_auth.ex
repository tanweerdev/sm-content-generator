defmodule SMG.Integrations.FacebookAuth do
  @moduledoc """
  Facebook OAuth 2.0 authentication and token refresh functionality
  """

  use Tesla
  require Logger

  plug Tesla.Middleware.BaseUrl, "https://graph.facebook.com"
  plug Tesla.Middleware.JSON

  @doc """
  Refreshes a Facebook OAuth access token using the refresh token
  """
  def refresh_token(refresh_token) do
    Logger.info("Attempting to refresh Facebook OAuth token")

    params = %{
      grant_type: "refresh_token",
      refresh_token: refresh_token,
      client_id: facebook_app_id(),
      client_secret: facebook_app_secret()
    }

    case get("/oauth/access_token", query: params) do
      {:ok, %{status: 200, body: response}} ->
        Logger.info("Successfully refreshed Facebook OAuth token")

        # Facebook returns different response formats, normalize it
        token_data =
          case response do
            %{"access_token" => _} = data ->
              # Add expires_in if not present (Facebook sometimes omits it)
              Map.put_new(data, "expires_in", 3600)

            # Handle string response format
            response_string when is_binary(response_string) ->
              parse_facebook_token_response(response_string)

            _ ->
              response
          end

        {:ok, token_data}

      {:ok, %{status: status, body: error}} ->
        Logger.error("Failed to refresh Facebook OAuth token",
          status: status,
          error: error
        )

        {:error, "Failed to refresh token: #{status} - #{inspect(error)}"}

      {:error, reason} ->
        Logger.error("Facebook OAuth token refresh API request failed", reason: reason)
        {:error, "API request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Exchanges a short-lived token for a long-lived token
  Facebook tokens typically last 60 days when exchanged for long-lived tokens
  """
  def exchange_for_long_lived_token(short_lived_token) do
    Logger.info("Exchanging Facebook short-lived token for long-lived token")

    params = %{
      grant_type: "fb_exchange_token",
      client_id: facebook_app_id(),
      client_secret: facebook_app_secret(),
      fb_exchange_token: short_lived_token
    }

    case get("/oauth/access_token", query: params) do
      {:ok, %{status: 200, body: response}} ->
        Logger.info("Successfully exchanged for Facebook long-lived token")

        token_data =
          case response do
            %{"access_token" => _} = data ->
              # Set expires_in to 60 days for long-lived tokens
              Map.put(data, "expires_in", 60 * 24 * 3600)

            response_string when is_binary(response_string) ->
              parse_facebook_token_response(response_string)

            _ ->
              response
          end

        {:ok, token_data}

      {:ok, %{status: status, body: error}} ->
        Logger.error("Failed to exchange Facebook token",
          status: status,
          error: error
        )

        {:error, "Failed to exchange token: #{status} - #{inspect(error)}"}

      {:error, reason} ->
        Logger.error("Facebook token exchange API request failed", reason: reason)
        {:error, "API request failed: #{inspect(reason)}"}
    end
  end

  defp parse_facebook_token_response(response_string) do
    # Parse Facebook's query string response format
    # e.g., "access_token=ABC123&expires_in=3600"
    response_string
    |> String.split("&")
    |> Enum.reduce(%{}, fn param, acc ->
      case String.split(param, "=", parts: 2) do
        [key, value] -> Map.put(acc, key, value)
        _ -> acc
      end
    end)
    |> Map.update("expires_in", 3600, fn val ->
      case Integer.parse(val) do
        {int_val, _} -> int_val
        _ -> 3600
      end
    end)
  end

  defp facebook_app_id do
    System.get_env("FACEBOOK_APP_ID") ||
      raise "FACEBOOK_APP_ID environment variable not set"
  end

  defp facebook_app_secret do
    System.get_env("FACEBOOK_APP_SECRET") ||
      raise "FACEBOOK_APP_SECRET environment variable not set"
  end
end
