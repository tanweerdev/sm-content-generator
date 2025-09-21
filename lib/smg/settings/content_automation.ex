defmodule SMG.Settings.ContentAutomation do
  use Ecto.Schema
  import Ecto.Changeset

  alias SMG.Accounts.User

  schema "content_automations" do
    field :name, :string
    field :platform, :string
    field :content_type, :string
    field :prompt_template, :string
    field :enabled, :boolean, default: true
    field :auto_publish, :boolean, default: false

    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(content_automation, attrs) do
    content_automation
    |> cast(attrs, [
      :name,
      :platform,
      :content_type,
      :prompt_template,
      :enabled,
      :auto_publish,
      :user_id
    ])
    |> validate_required([:name, :platform, :content_type, :user_id])
    |> validate_inclusion(:platform, ["linkedin", "facebook"])
    |> validate_inclusion(:content_type, [
      "marketing",
      "educational",
      "insights",
      "summary",
      "takeaways"
    ])
  end
end
