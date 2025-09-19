defmodule SMG.Integrations.LinkedIn do
  @moduledoc """
  LinkedIn API integration for posting content
  """

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://api.linkedin.com/v2"
  plug Tesla.Middleware.JSON

  alias SMG.Social.SocialPost
  alias SMG.Accounts.User

  @doc """
  Posts content to LinkedIn using user's access token
  """
  def post_content(%SocialPost{} = social_post, access_token) do
    headers = [{"Authorization", "Bearer #{access_token}"}]

    body = %{
      author: "urn:li:person:#{get_linkedin_user_id(access_token)}",
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
        {:error, "Failed to post to LinkedIn: #{status} - #{inspect(error)}"}

      {:error, reason} ->
        {:error, "API request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Gets the LinkedIn user ID for the authenticated user
  """
  defp get_linkedin_user_id(access_token) do
    headers = [{"Authorization", "Bearer #{access_token}"}]

    case get("/me", headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        response["id"]

      _ ->
        # Fallback - in a real app you'd store this during OAuth
        "placeholder-user-id"
    end
  end

  @doc """
  Simulates posting to LinkedIn (for demo purposes)
  """
  def simulate_post(%SocialPost{} = social_post) do
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