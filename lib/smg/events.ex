defmodule SMG.Events do
  @moduledoc """
  The Events context.
  """

  import Ecto.Query, warn: false
  alias SMG.Repo

  alias SMG.Events.CalendarEvent
  alias SMG.Accounts.{User, GoogleAccount}

  @doc """
  Returns the list of calendar events for a user.
  """
  def list_events_for_user(%User{} = user) do
    from(e in CalendarEvent,
      join: g in GoogleAccount,
      on: e.google_account_id == g.id,
      where: g.user_id == ^user.id,
      order_by: [asc: e.start_time],
      preload: [:google_account]
    )
    |> Repo.all()
  end

  @doc """
  Returns the list of upcoming calendar events for a user.
  """
  def list_upcoming_events_for_user(%User{} = user, limit \\ 50) do
    now = DateTime.utc_now()

    from(e in CalendarEvent,
      join: g in GoogleAccount,
      on: e.google_account_id == g.id,
      where: g.user_id == ^user.id and not is_nil(e.start_time) and e.start_time > ^now,
      order_by: [asc: e.start_time],
      limit: ^limit,
      preload: [:google_account, :social_posts]
    )
    |> Repo.all()
  end

  @doc """
  Returns the list of past calendar events for a user.
  """
  def list_past_events_for_user(%User{} = user, limit \\ 50) do
    now = DateTime.utc_now()

    from(e in CalendarEvent,
      join: g in GoogleAccount,
      on: e.google_account_id == g.id,
      where: g.user_id == ^user.id and not is_nil(e.start_time) and e.start_time <= ^now,
      order_by: [desc: e.start_time],
      limit: ^limit,
      preload: [:google_account, :social_posts]
    )
    |> Repo.all()
  end

  @doc """
  Returns events that are currently happening (between start_time and end_time).
  """
  def list_current_events_for_user(%User{} = user) do
    now = DateTime.utc_now()

    from(e in CalendarEvent,
      join: g in GoogleAccount,
      on: e.google_account_id == g.id,
      where:
        g.user_id == ^user.id and
          not is_nil(e.start_time) and
          not is_nil(e.end_time) and
          e.start_time <= ^now and
          e.end_time > ^now,
      order_by: [asc: e.start_time],
      preload: [:google_account, :social_posts]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single calendar event.
  """
  def get_event!(id), do: Repo.get!(CalendarEvent, id)

  @doc """
  Gets a calendar event by Google event ID.
  """
  def get_event_by_google_id(google_event_id) do
    Repo.get_by(CalendarEvent, google_event_id: google_event_id)
  end

  @doc """
  Gets a calendar event by Recall bot ID.
  """
  def get_event_by_recall_bot_id(recall_bot_id) do
    Repo.get_by(CalendarEvent, recall_bot_id: recall_bot_id)
  end

  @doc """
  Creates a calendar event.
  """
  def create_event(attrs \\ %{}) do
    %CalendarEvent{}
    |> CalendarEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a calendar event.
  """
  def update_event(%CalendarEvent{} = calendar_event, attrs) do
    calendar_event
    |> CalendarEvent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a calendar event.
  """
  def delete_event(%CalendarEvent{} = calendar_event) do
    Repo.delete(calendar_event)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking calendar event changes.
  """
  def change_event(%CalendarEvent{} = calendar_event, attrs \\ %{}) do
    CalendarEvent.changeset(calendar_event, attrs)
  end

  @doc """
  Toggles the notetaker setting for an event.
  """
  def toggle_notetaker(%CalendarEvent{} = event) do
    update_event(event, %{notetaker_enabled: !event.notetaker_enabled})
  end

  @doc """
  Gets events with notetaker enabled that have meeting links.
  """
  def list_events_with_notetaker_enabled do
    from(e in CalendarEvent,
      where: e.notetaker_enabled == true and not is_nil(e.meeting_link),
      preload: [:google_account]
    )
    |> Repo.all()
  end
end
