defmodule SMG.Services.SocialMediaPoster do
  @moduledoc """
  Service for posting content to social media platforms
  """

  alias SMG.Social
  alias SMG.Social.SocialPost
  alias SMG.Integrations.LinkedIn

  @doc """
  Posts a social media post to the specified platform
  """
  def post_to_platform(%SocialPost{} = social_post) do
    case social_post.platform do
      "linkedin" ->
        post_to_linkedin(social_post)

      "twitter" ->
        post_to_twitter(social_post)

      platform ->
        {:error, "Unsupported platform: #{platform}"}
    end
  end

  defp post_to_linkedin(%SocialPost{} = social_post) do
    # For demo purposes, we'll simulate the posting
    # In a real implementation, you'd get the user's LinkedIn access token
    # and use the LinkedIn.post_content/2 function
    case LinkedIn.simulate_post(social_post) do
      {:ok, platform_post_id} ->
        case Social.mark_as_posted(social_post, platform_post_id) do
          {:ok, updated_post} ->
            {:ok, updated_post}

          {:error, changeset} ->
            {:error, "Failed to update post status: #{inspect(changeset)}"}
        end

      {:error, reason} ->
        Social.mark_as_failed(social_post)
        {:error, reason}
    end
  end

  defp post_to_twitter(%SocialPost{} = social_post) do
    # Twitter posting would be implemented here
    # For now, we'll simulate it
    case simulate_twitter_post(social_post) do
      {:ok, platform_post_id} ->
        Social.mark_as_posted(social_post, platform_post_id)

      {:error, reason} ->
        Social.mark_as_failed(social_post)
        {:error, reason}
    end
  end

  defp simulate_twitter_post(%SocialPost{} = social_post) do
    # Simulate Twitter API
    Process.sleep(800)

    case :rand.uniform(10) do
      n when n <= 9 ->
        platform_post_id = "twitter_post_#{System.unique_integer([:positive])}"
        {:ok, platform_post_id}

      _ ->
        {:error, "Simulated Twitter API error"}
    end
  end

  @doc """
  Posts multiple social media posts in parallel
  """
  def post_multiple(social_posts) when is_list(social_posts) do
    social_posts
    |> Enum.map(&Task.async(fn -> post_to_platform(&1) end))
    |> Enum.map(&Task.await/1)
  end
end