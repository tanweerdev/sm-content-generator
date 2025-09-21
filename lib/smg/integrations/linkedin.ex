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
    post_to_linkedin(connection.access_token, social_post, connection.platform_user_id)
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
end
