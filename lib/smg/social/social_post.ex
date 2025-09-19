defmodule SMG.Social.SocialPost do
  use Ecto.Schema
  import Ecto.Changeset

  alias SMG.Accounts.User
  alias SMG.Events.CalendarEvent

  schema "social_posts" do
    field :content, :string
    field :platform, :string
    field :posted_at, :utc_datetime
    field :status, :string, default: "draft"
    field :platform_post_id, :string
    field :generated_from_transcript, :boolean, default: true

    belongs_to :user, User
    belongs_to :calendar_event, CalendarEvent

    timestamps()
  end

  @doc false
  def changeset(social_post, attrs) do
    social_post
    |> cast(attrs, [
      :content, :platform, :posted_at, :status, :platform_post_id,
      :generated_from_transcript, :user_id, :calendar_event_id
    ])
    |> validate_required([:content, :user_id, :calendar_event_id])
    |> validate_inclusion(:platform, ["linkedin", "twitter", "facebook"])
    |> validate_inclusion(:status, ["draft", "posted", "failed"])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:calendar_event_id)
  end
end