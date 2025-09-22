defmodule SMG.Integrations.Facebook do
  @moduledoc """
  Facebook API integration for posting content to Facebook Pages
  """

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://graph.facebook.com/v18.0"
  plug Tesla.Middleware.JSON

  alias SMG.Social.SocialPost

  @doc """
  Posts content to Facebook personal profile using user's connected account or environment variables as fallback
  """
  def post_content(%SMG.Settings.SocialConnection{} = connection, %SocialPost{} = social_post) do
    post_to_facebook_with_retry(connection, social_post, false)
  end

  def post_content(nil, %SocialPost{} = social_post) do
    # First try to get user's Facebook connection
    user = SMG.Accounts.get_user(social_post.user_id)
    facebook_connection = SMG.Settings.get_social_connection(user, "facebook")

    if facebook_connection && facebook_connection.access_token do
      post_to_facebook_profile(facebook_connection.access_token, social_post)
    else
      # Fall back to environment variables (for development/testing)
      access_token = System.get_env("FACEBOOK_ACCESS_TOKEN")

      if access_token do
        post_to_facebook_profile(access_token, social_post)
      else
        {:error, "No Facebook connection found. Please connect your Facebook account."}
      end
    end
  end

  defp post_to_facebook_profile(access_token, %SocialPost{} = social_post) do
    # Post to personal Facebook profile feed
    endpoint = "/me/feed"

    body = %{
      message: social_post.content,
      access_token: access_token
    }

    headers = [{"Authorization", "Bearer #{access_token}"}]

    case post(endpoint, body, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response["id"]}

      {:ok, %{status: status, body: error}} ->
        error_message = extract_facebook_error(error)
        {:error, "Failed to post to Facebook profile: #{status} - #{error_message}"}

      {:error, reason} ->
        {:error, "API request failed: #{inspect(reason)}"}
    end
  end

  defp extract_facebook_error(%{"error" => %{"message" => message}}), do: message
  defp extract_facebook_error(error), do: inspect(error)

  @doc """
  Simulates posting to Facebook (for demo purposes)
  """
  def simulate_post(%SocialPost{} = _social_post) do
    # Simulate API delay
    Process.sleep(600)

    # Simulate success/failure
    case :rand.uniform(10) do
      n when n <= 9 ->
        platform_post_id = "facebook_post_#{System.unique_integer([:positive])}"
        {:ok, platform_post_id}

      _ ->
        {:error, "Simulated Facebook API error"}
    end
  end

  defp post_to_facebook_with_retry(%SMG.Settings.SocialConnection{} = connection, %SocialPost{} = social_post, retried?) do
    require Logger

    Logger.info("Attempting to post to Facebook",
      user_id: social_post.user_id,
      platform_user_id: connection.platform_user_id,
      retried: retried?
    )

    case post_to_facebook_profile(connection.access_token, social_post) do
      {:ok, platform_post_id} ->
        {:ok, platform_post_id}

      {:error, error_message} ->
        # Check if this is a token expiry error and we haven't retried yet
        if is_token_expired_error?(error_message) and not retried? do
          Logger.info("Facebook token expired, attempting to refresh and retry",
            user_id: social_post.user_id,
            platform_user_id: connection.platform_user_id
          )

          case refresh_facebook_token_and_retry(connection, social_post) do
            {:ok, platform_post_id} -> {:ok, platform_post_id}
            {:error, reason} -> {:error, reason}
          end
        else
          {:error, error_message}
        end
    end
  end

  defp is_token_expired_error?(error_message) when is_binary(error_message) do
    error_lower = String.downcase(error_message)

    String.contains?(error_lower, [
      "unauthorized",
      "token expired",
      "invalid_token",
      "invalid credentials",
      "access token is invalid",
      "expired token",
      "token has expired",
      "error validating access token",
      "session has expired",
      "token is invalid",
      "401",
      "190"  # Facebook's invalid token error code
    ])
  end

  defp is_token_expired_error?(_), do: false

  defp refresh_facebook_token_and_retry(%SMG.Settings.SocialConnection{} = connection, %SocialPost{} = social_post) do
    require Logger

    Logger.info("Attempting to refresh Facebook OAuth token",
      user_id: social_post.user_id,
      platform_user_id: connection.platform_user_id
    )

    case SMG.Integrations.FacebookAuth.refresh_token(connection.refresh_token) do
      {:ok, token_data} ->
        # Update the connection with new token
        update_attrs = %{
          access_token: token_data["access_token"],
          expires_at: DateTime.add(DateTime.utc_now(), token_data["expires_in"], :second)
        }

        # Add new refresh token if provided
        update_attrs =
          if token_data["refresh_token"] do
            Map.put(update_attrs, :refresh_token, token_data["refresh_token"])
          else
            update_attrs
          end

        case SMG.Settings.update_social_connection(connection, update_attrs) do
          {:ok, updated_connection} ->
            Logger.info("Successfully refreshed Facebook token, retrying post",
              user_id: social_post.user_id,
              new_expires_at: updated_connection.expires_at
            )

            # Retry the post with the updated connection
            post_to_facebook_with_retry(updated_connection, social_post, true)

          {:error, changeset} ->
            Logger.error("Failed to update Facebook connection with refreshed token",
              user_id: social_post.user_id,
              errors: inspect(changeset.errors)
            )

            {:error, "Failed to update connection with new token"}
        end

      {:error, reason} ->
        Logger.error("Failed to refresh Facebook OAuth token",
          user_id: social_post.user_id,
          reason: reason
        )

        {:error, "Token refresh failed: #{reason}"}
    end
  end
end
