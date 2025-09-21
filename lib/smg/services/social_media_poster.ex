defmodule SMG.Services.SocialMediaPoster do
  @moduledoc """
  Service for posting content to social media platforms
  """

  alias SMG.Social
  alias SMG.Social.SocialPost
  alias SMG.Integrations.LinkedIn
  alias SMG.Integrations.Facebook

  @doc """
  Posts a social media post to the specified platform
  """
  def post_to_platform(%SocialPost{} = social_post) do
    case social_post.platform do
      "linkedin" ->
        post_to_linkedin(social_post)

      "facebook" ->
        post_to_facebook(social_post)

      platform ->
        {:error, "Unsupported platform: #{platform}"}
    end
  end

  defp post_to_linkedin(%SocialPost{} = social_post) do
    # Get the user's LinkedIn connection
    user = SMG.Accounts.get_user(social_post.user_id)
    linkedin_connection = SMG.Settings.get_social_connection(user, "linkedin")

    if linkedin_connection do
      case LinkedIn.post_content(linkedin_connection, social_post) do
        {:ok, platform_post_id} ->
          case Social.mark_as_posted(social_post, platform_post_id) do
            {:ok, updated_post} ->
              {:ok, updated_post}

            {:error, _changeset} ->
              {:error, "Failed to update post status"}
          end

        {:error, reason} ->
          Social.mark_as_failed(social_post)
          {:error, reason}
      end
    else
      # No LinkedIn connection found
      Social.mark_as_failed(social_post)
      {:error, "Please connect your LinkedIn account first from Settings page"}
    end
  end

  defp post_to_facebook(%SocialPost{} = social_post) do
    # Get the user's Facebook connection
    user = SMG.Accounts.get_user(social_post.user_id)
    facebook_connection = SMG.Settings.get_social_connection(user, "facebook")

    if facebook_connection do
      case Facebook.post_content(facebook_connection, social_post) do
        {:ok, platform_post_id} ->
          case Social.mark_as_posted(social_post, platform_post_id) do
            {:ok, updated_post} ->
              {:ok, updated_post}

            {:error, _changeset} ->
              {:error, "Failed to update post status"}
          end

        {:error, reason} ->
          Social.mark_as_failed(social_post)
          {:error, reason}
      end
    else
      # No Facebook connection found
      Social.mark_as_failed(social_post)
      {:error, "Please connect your Facebook account first from Settings page"}
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
