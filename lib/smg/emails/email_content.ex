defmodule SMG.Emails.EmailContent do
  use Ecto.Schema
  import Ecto.Changeset

  alias SMG.Accounts.User
  alias SMG.Events.CalendarEvent

  schema "email_contents" do
    field :subject, :string
    field :body, :string
    field :email_type, :string
    field :status, :string, default: "draft"
    field :generated_from_transcript, :boolean, default: true
    field :recipient_email, :string
    field :recipient_name, :string

    belongs_to :user, User
    belongs_to :calendar_event, CalendarEvent

    timestamps()
  end

  @doc false
  def changeset(email_content, attrs) do
    email_content
    |> cast(attrs, [
      :subject,
      :body,
      :email_type,
      :status,
      :generated_from_transcript,
      :recipient_email,
      :recipient_name,
      :user_id,
      :calendar_event_id
    ])
    |> validate_required([:subject, :body, :email_type, :user_id])
    |> validate_inclusion(:email_type, [
      "followup",
      "thank_you",
      "meeting_summary",
      "action_items",
      "reminder",
      "introduction"
    ])
    |> validate_inclusion(:status, ["draft", "sent", "archived"])
    |> validate_format(:recipient_email, ~r/@/, message: "must be a valid email")
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:calendar_event_id)
  end
end