defmodule SMG.Settings do
  @moduledoc """
  The Settings context for managing user preferences and configurations.
  """

  import Ecto.Query, warn: false
  alias SMG.Repo

  alias SMG.Settings.{BotSettings, SocialConnection, ContentAutomation}
  alias SMG.Accounts.User

  @doc """
  Gets connected social media platforms for a user.
  """
  def get_connected_platforms(%User{} = user) do
    from(sc in SocialConnection,
      where: sc.user_id == ^user.id,
      select: {sc.platform, sc}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Gets or creates bot settings for a user.
  """
  def get_bot_settings(%User{} = user) do
    case Repo.get_by(BotSettings, user_id: user.id) do
      nil ->
        %BotSettings{
          user_id: user.id,
          join_minutes_before: 5
        }

      settings ->
        settings
    end
  end

  @doc """
  Updates bot settings for a user.
  """
  def update_bot_settings(%User{} = user, attrs) do
    case Repo.get_by(BotSettings, user_id: user.id) do
      nil ->
        %BotSettings{user_id: user.id}
        |> BotSettings.changeset(attrs)
        |> Repo.insert()

      existing_settings ->
        existing_settings
        |> BotSettings.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Lists all content automations for a user.
  """
  def list_automations(%User{} = user) do
    from(ca in ContentAutomation,
      where: ca.user_id == ^user.id,
      order_by: [desc: ca.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Creates or updates a content automation.
  """
  def create_or_update_automation(%User{} = user, attrs) do
    %ContentAutomation{user_id: user.id}
    |> ContentAutomation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes a content automation.
  """
  def delete_automation(automation_id) do
    case Repo.get(ContentAutomation, automation_id) do
      nil ->
        {:error, "Automation not found"}

      automation ->
        Repo.delete(automation)
    end
  end

  @doc """
  Connects a social media platform for a user.
  """
  def connect_social_platform(%User{} = user, platform, platform_data) do
    attrs = %{
      user_id: user.id,
      platform: platform,
      platform_user_id: platform_data.platform_user_id,
      email: platform_data.email,
      access_token: platform_data.access_token,
      refresh_token: platform_data.refresh_token,
      expires_at: platform_data.expires_at,
      scope: platform_data.scope
    }

    case Repo.get_by(SocialConnection, user_id: user.id, platform: platform) do
      nil ->
        %SocialConnection{}
        |> SocialConnection.changeset(attrs)
        |> Repo.insert()

      existing_connection ->
        existing_connection
        |> SocialConnection.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Disconnects a social media platform for a user.
  """
  def disconnect_social_platform(%User{} = user, platform) do
    case Repo.get_by(SocialConnection, user_id: user.id, platform: platform) do
      nil ->
        {:error, "Platform not connected"}

      connection ->
        Repo.delete(connection)
    end
  end

  @doc """
  Gets active automations for a specific platform and user.
  """
  def get_active_automations(%User{} = user, platform) do
    from(ca in ContentAutomation,
      where: ca.user_id == ^user.id and ca.platform == ^platform and ca.enabled == true
    )
    |> Repo.all()
  end

  @doc """
  Gets a social connection for a platform.
  """
  def get_social_connection(%User{} = user, platform) do
    Repo.get_by(SocialConnection, user_id: user.id, platform: platform)
  end

  @doc """
  Updates a social connection with new attributes.
  """
  def update_social_connection(%SocialConnection{} = social_connection, attrs) do
    social_connection
    |> SocialConnection.changeset(attrs)
    |> Repo.update()
  end
end
