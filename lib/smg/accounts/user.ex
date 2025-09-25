defmodule SMG.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias SMG.Accounts.GoogleAccount
  alias SMG.Social.SocialPost
  alias SMG.Emails.EmailContent

  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar_url, :string

    has_many :google_accounts, GoogleAccount
    has_many :calendar_events, through: [:google_accounts, :calendar_events]
    has_many :social_posts, SocialPost
    has_many :email_contents, EmailContent

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :avatar_url])
    |> validate_required([:email])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
  end
end
