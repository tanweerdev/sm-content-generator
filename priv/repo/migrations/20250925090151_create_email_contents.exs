defmodule SMG.Repo.Migrations.CreateEmailContents do
  use Ecto.Migration

  def change do
    create table(:email_contents) do
      add :subject, :string, null: false
      add :body, :text, null: false
      add :email_type, :string, null: false
      add :status, :string, default: "draft"
      add :generated_from_transcript, :boolean, default: true
      add :recipient_email, :string
      add :recipient_name, :string

      add :user_id, references(:users, on_delete: :nothing), null: false
      add :calendar_event_id, references(:calendar_events, on_delete: :nothing)

      timestamps()
    end

    create index(:email_contents, [:user_id])
    create index(:email_contents, [:calendar_event_id])
    create index(:email_contents, [:email_type])
    create index(:email_contents, [:status])
  end
end
