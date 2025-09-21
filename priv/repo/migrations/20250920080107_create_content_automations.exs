defmodule SMG.Repo.Migrations.CreateContentAutomations do
  use Ecto.Migration

  def change do
    create table(:content_automations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :platform, :string, null: false
      add :content_type, :string, null: false
      add :prompt_template, :text
      add :enabled, :boolean, default: true
      add :auto_publish, :boolean, default: false

      timestamps()
    end

    create index(:content_automations, [:user_id])
    create index(:content_automations, [:platform])
    create index(:content_automations, [:enabled])
  end
end
