defmodule SMG.Settings.SocialConnection do
  use Ecto.Schema
  import Ecto.Changeset

  alias SMG.Accounts.User

  schema "social_connections" do
    field :platform, :string
    field :platform_user_id, :string
    field :email, :string
    field :access_token, :string
    field :refresh_token, :string
    field :expires_at, :utc_datetime
    field :scope, :string

    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(social_connection, attrs) do
    social_connection
    |> cast(attrs, [
      :platform,
      :platform_user_id,
      :email,
      :access_token,
      :refresh_token,
      :expires_at,
      :scope,
      :user_id
    ])
    |> validate_required([:platform, :platform_user_id, :email, :access_token, :user_id])
    |> validate_inclusion(:platform, ["linkedin", "facebook"])
    |> unique_constraint([:user_id, :platform])
  end
end
