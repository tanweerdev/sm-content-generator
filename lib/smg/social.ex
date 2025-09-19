defmodule SMG.Social do
  @moduledoc """
  The Social context.
  """

  import Ecto.Query, warn: false
  alias SMG.Repo

  alias SMG.Social.SocialPost
  alias SMG.Accounts.User

  @doc """
  Returns the list of social posts for a user.
  """
  def list_social_posts_for_user(%User{} = user) do
    from(p in SocialPost,
      where: p.user_id == ^user.id,
      order_by: [desc: p.inserted_at],
      preload: [:calendar_event]
    )
    |> Repo.all()
  end

  @doc """
  Returns the list of draft social posts for a user.
  """
  def list_draft_posts_for_user(%User{} = user) do
    from(p in SocialPost,
      where: p.user_id == ^user.id and p.status == "draft",
      order_by: [desc: p.inserted_at],
      preload: [:calendar_event]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single social post.
  """
  def get_social_post!(id), do: Repo.get!(SocialPost, id)

  @doc """
  Gets a single social post for a user.
  """
  def get_social_post_for_user!(id, %User{} = user) do
    from(p in SocialPost,
      where: p.id == ^id and p.user_id == ^user.id,
      preload: [:calendar_event]
    )
    |> Repo.one!()
  end

  @doc """
  Creates a social post.
  """
  def create_social_post(attrs \\ %{}) do
    %SocialPost{}
    |> SocialPost.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a social post.
  """
  def update_social_post(%SocialPost{} = social_post, attrs) do
    social_post
    |> SocialPost.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a social post.
  """
  def delete_social_post(%SocialPost{} = social_post) do
    Repo.delete(social_post)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking social post changes.
  """
  def change_social_post(%SocialPost{} = social_post, attrs \\ %{}) do
    SocialPost.changeset(social_post, attrs)
  end

  @doc """
  Marks a social post as posted.
  """
  def mark_as_posted(%SocialPost{} = social_post, platform_post_id \\ nil) do
    update_social_post(social_post, %{
      status: "posted",
      posted_at: DateTime.utc_now(),
      platform_post_id: platform_post_id
    })
  end

  @doc """
  Marks a social post as failed.
  """
  def mark_as_failed(%SocialPost{} = social_post) do
    update_social_post(social_post, %{status: "failed"})
  end
end