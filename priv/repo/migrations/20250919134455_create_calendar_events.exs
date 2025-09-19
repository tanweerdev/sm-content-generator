defmodule SMG.Repo.Migrations.CreateCalendarEvents do
  use Ecto.Migration

  def change do
    create table(:calendar_events) do
      add :google_account_id, references(:google_accounts, on_delete: :delete_all), null: false
      add :google_event_id, :string, null: false
      add :title, :string
      add :description, :text
      add :start_time, :utc_datetime
      add :end_time, :utc_datetime
      add :zoom_link, :string
      add :meeting_link, :string
      add :notetaker_enabled, :boolean, default: false
      add :recall_bot_id, :string
      add :transcript_url, :string
      add :transcript_status, :string

      timestamps()
    end

    create index(:calendar_events, [:google_account_id])
    create unique_index(:calendar_events, [:google_event_id])
    create index(:calendar_events, [:start_time])
  end
end
