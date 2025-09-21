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
    post_to_facebook_profile(connection.access_token, social_post)
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
end
