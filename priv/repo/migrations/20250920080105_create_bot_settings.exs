defmodule SMG.Repo.Migrations.CreateBotSettings do
  use Ecto.Migration

  def change do
    create table(:bot_settings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :join_minutes_before, :integer, default: 5

      timestamps()
    end

    create unique_index(:bot_settings, [:user_id])
  end
end
