defmodule SMG.Repo.Migrations.CreateSocialConnections do
  use Ecto.Migration

  def change do
    create table(:social_connections) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :platform, :string, null: false
      add :platform_user_id, :string, null: false
      add :email, :string, null: false
      add :access_token, :text, null: false
      add :refresh_token, :text
      add :expires_at, :utc_datetime
      add :scope, :string

      timestamps()
    end

    create unique_index(:social_connections, [:user_id, :platform])
    create index(:social_connections, [:platform])
  end
end
