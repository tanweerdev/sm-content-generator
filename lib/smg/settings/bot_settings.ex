defmodule SMG.Settings.BotSettings do
  use Ecto.Schema
  import Ecto.Changeset

  alias SMG.Accounts.User

  schema "bot_settings" do
    field :join_minutes_before, :integer, default: 5

    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(bot_settings, attrs) do
    bot_settings
    |> cast(attrs, [:join_minutes_before, :user_id])
    |> validate_required([:join_minutes_before, :user_id])
    |> validate_inclusion(:join_minutes_before, 1..30)
    |> unique_constraint(:user_id)
  end
end
