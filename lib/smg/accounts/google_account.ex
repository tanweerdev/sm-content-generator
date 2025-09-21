defmodule SMG.Accounts.GoogleAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias SMG.Accounts.User
  alias SMG.Events.CalendarEvent

  schema "google_accounts" do
    field :google_user_id, :string
    field :email, :string
    field :access_token, :string
    field :refresh_token, :string
    field :expires_at, :utc_datetime
    field :scope, :string

    belongs_to :user, User
    has_many :calendar_events, CalendarEvent

    timestamps()
  end

  @doc false
  def changeset(google_account, attrs) do
    google_account
    |> cast(attrs, [
      :google_user_id,
      :email,
      :access_token,
      :refresh_token,
      :expires_at,
      :scope,
      :user_id
    ])
    |> validate_required([:google_user_id, :email, :user_id])
    |> unique_constraint(:google_user_id)
    |> foreign_key_constraint(:user_id)
  end
end
