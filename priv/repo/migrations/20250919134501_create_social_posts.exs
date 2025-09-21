defmodule SMG.Repo.Migrations.CreateSocialPosts do
  use Ecto.Migration

  def change do
    create table(:social_posts) do
      add :calendar_event_id, references(:calendar_events, on_delete: :delete_all), null: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :content, :text, null: false
      # linkedin, facebook, etc
      add :platform, :string
      add :posted_at, :utc_datetime
      # draft, posted, failed
      add :status, :string, default: "draft"
      add :platform_post_id, :string
      add :generated_from_transcript, :boolean, default: true

      timestamps()
    end

    create index(:social_posts, [:calendar_event_id])
    create index(:social_posts, [:user_id])
    create index(:social_posts, [:status])
  end
end
