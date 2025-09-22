defmodule SMG.Integrations.LinkedIn do
  @moduledoc """
  LinkedIn API integration for posting content
  """

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://api.linkedin.com/v2"
  plug Tesla.Middleware.JSON

  alias SMG.Social.SocialPost

  @doc """
  Posts content to LinkedIn using user's connected account or environment variables as fallback
  """
  def post_content(%SMG.Settings.SocialConnection{} = connection, %SocialPost{} = social_post) do
    post_to_linkedin_with_retry(connection, social_post, false)
  end

  def post_content(nil, %SocialPost{} = social_post) do
    # First try to get user's LinkedIn connection
    user = SMG.Accounts.get_user(social_post.user_id)
    linkedin_connection = SMG.Settings.get_social_connection(user, "linkedin")

    if linkedin_connection && linkedin_connection.access_token do
      post_to_linkedin(
        linkedin_connection.access_token,
        social_post,
        linkedin_connection.platform_user_id
      )
    else
      # Fall back to environment variables (for development/testing)
      access_token = System.get_env("LINKEDIN_ACCESS_TOKEN")

      if access_token do
        # Get LinkedIn user ID from the token
        case get_linkedin_user_id(access_token) do
          {:ok, user_id} ->
            post_to_linkedin(access_token, social_post, user_id)

          {:error, reason} ->
            {:error, "Failed to get LinkedIn user ID: #{reason}"}
        end
      else
        {:error, "No LinkedIn connection found. Please connect your LinkedIn account."}
      end
    end
  end

  defp post_to_linkedin(access_token, %SocialPost{} = social_post, user_id) do
    headers = [{"Authorization", "Bearer #{access_token}"}]

    body = %{
      author: "urn:li:person:#{user_id}",
      lifecycleState: "PUBLISHED",
      specificContent: %{
        "com.linkedin.ugc.ShareContent" => %{
          shareCommentary: %{
            text: social_post.content
          },
          shareMediaCategory: "NONE"
        }
      },
      visibility: %{
        "com.linkedin.ugc.MemberNetworkVisibility" => "PUBLIC"
      }
    }

    case post("/ugcPosts", body, headers: headers) do
      {:ok, %{status: 201, body: response}} ->
        {:ok, response["id"]}

      {:ok, %{status: status, body: error}} ->
        error_message = extract_linkedin_error(error)
        {:error, "Failed to post to LinkedIn: #{status} - #{error_message}"}

      {:error, reason} ->
        {:error, "API request failed: #{inspect(reason)}"}
    end
  end

  defp extract_linkedin_error(%{"message" => message}), do: message
  defp extract_linkedin_error(%{"error" => %{"message" => message}}), do: message
  defp extract_linkedin_error(error), do: inspect(error)

  defp get_linkedin_user_id(access_token) do
    headers = [{"Authorization", "Bearer #{access_token}"}]

    case get("/me", headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response["id"]}

      {:ok, %{status: status, body: error}} ->
        error_message = extract_linkedin_error(error)
        {:error, "Failed to get user profile: #{status} - #{error_message}"}

      {:error, reason} ->
        {:error, "API request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Simulates posting to LinkedIn (for demo purposes)
  """
  def simulate_post(%SocialPost{} = _social_post) do
    # Simulate API delay
    Process.sleep(1000)

    # Simulate success/failure
    case :rand.uniform(10) do
      n when n <= 8 ->
        platform_post_id = "linkedin_post_#{System.unique_integer([:positive])}"
        {:ok, platform_post_id}

      _ ->
        {:error, "Simulated LinkedIn API error"}
    end
  end

  defp post_to_linkedin_with_retry(%SMG.Settings.SocialConnection{} = connection, %SocialPost{} = social_post, retried?) do
    require Logger

    Logger.info("Attempting to post to LinkedIn",
      user_id: social_post.user_id,
      platform_user_id: connection.platform_user_id,
      retried: retried?
    )

    case post_to_linkedin(connection.access_token, social_post, connection.platform_user_id) do
      {:ok, platform_post_id} ->
        {:ok, platform_post_id}

      {:error, error_message} ->
        # Check if this is a token expiry error and we haven't retried yet
        if is_token_expired_error?(error_message) and not retried? do
          Logger.info("LinkedIn token expired, attempting to refresh and retry",
            user_id: social_post.user_id,
            platform_user_id: connection.platform_user_id
          )

          case refresh_linkedin_token_and_retry(connection, social_post) do
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
      "401"
    ])
  end

  defp is_token_expired_error?(_), do: false

  defp refresh_linkedin_token_and_retry(%SMG.Settings.SocialConnection{} = connection, %SocialPost{} = social_post) do
    require Logger

    Logger.info("Attempting to refresh LinkedIn OAuth token",
      user_id: social_post.user_id,
      platform_user_id: connection.platform_user_id
    )

    case SMG.Integrations.LinkedInAuth.refresh_token(connection.refresh_token) do
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
            Logger.info("Successfully refreshed LinkedIn token, retrying post",
              user_id: social_post.user_id,
              new_expires_at: updated_connection.expires_at
            )

            # Retry the post with the updated connection
            post_to_linkedin_with_retry(updated_connection, social_post, true)

          {:error, changeset} ->
            Logger.error("Failed to update LinkedIn connection with refreshed token",
              user_id: social_post.user_id,
              errors: inspect(changeset.errors)
            )

            {:error, "Failed to update connection with new token"}
        end

      {:error, reason} ->
        Logger.error("Failed to refresh LinkedIn OAuth token",
          user_id: social_post.user_id,
          reason: reason
        )

        {:error, "Token refresh failed: #{reason}"}
    end
  end
end
