defmodule SMG.Events.CalendarEvent do
  use Ecto.Schema
  import Ecto.Changeset

  alias SMG.Accounts.GoogleAccount
  alias SMG.Social.SocialPost
  alias SMG.Emails.EmailContent

  schema "calendar_events" do
    field :google_event_id, :string
    field :title, :string
    field :description, :string
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime
    field :zoom_link, :string
    field :meeting_link, :string
    field :notetaker_enabled, :boolean, default: false
    field :recall_bot_id, :string
    field :transcript_url, :string
    field :transcript_status, :string
    field :attendee_count, :integer, default: 0
    field :attendee_emails, {:array, :string}, default: []

    belongs_to :google_account, GoogleAccount
    has_many :social_posts, SocialPost
    has_many :email_contents, EmailContent

    timestamps()
  end

  @doc false
  def changeset(calendar_event, attrs) do
    calendar_event
    |> cast(attrs, [
      :google_event_id,
      :title,
      :description,
      :start_time,
      :end_time,
      :zoom_link,
      :meeting_link,
      :notetaker_enabled,
      :recall_bot_id,
      :transcript_url,
      :transcript_status,
      :google_account_id,
      :attendee_count,
      :attendee_emails
    ])
    |> validate_required([:google_event_id, :google_account_id])
    |> unique_constraint(:google_event_id)
    |> foreign_key_constraint(:google_account_id)
  end

  def extract_meeting_link(description) when is_binary(description) do
    # Look for Zoom links in the description
    zoom_regex = ~r/https:\/\/[a-zA-Z0-9-]+\.zoom\.us\/j\/\d+\?[^\s]*/
    meet_regex = ~r/https:\/\/meet\.google\.com\/[a-z0-9-]+/
    teams_regex = ~r/https:\/\/teams\.microsoft\.com\/l\/meetup-join\/[^\s]*/

    cond do
      String.match?(description, zoom_regex) ->
        Regex.run(zoom_regex, description) |> List.first()

      String.match?(description, meet_regex) ->
        Regex.run(meet_regex, description) |> List.first()

      String.match?(description, teams_regex) ->
        Regex.run(teams_regex, description) |> List.first()

      true ->
        nil
    end
  end

  def extract_meeting_link(_), do: nil
end
