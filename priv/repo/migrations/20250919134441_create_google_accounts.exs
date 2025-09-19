defmodule SMG.Repo.Migrations.CreateGoogleAccounts do
  use Ecto.Migration

  def change do
    create table(:google_accounts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :google_user_id, :string, null: false
      add :email, :string, null: false
      add :access_token, :text
      add :refresh_token, :text
      add :expires_at, :utc_datetime
      add :scope, :string

      timestamps()
    end

    create index(:google_accounts, [:user_id])
    create unique_index(:google_accounts, [:google_user_id])
  end
end
