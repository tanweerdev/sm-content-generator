defmodule SMG.Integrations.GoogleCalendar do
  @moduledoc """
  Google Calendar API integration
  """

  alias GoogleApi.Calendar.V3.Api.Events
  alias GoogleApi.Calendar.V3.Model.Event
  alias GoogleApi.Calendar.V3.Connection
  alias SMG.Accounts.GoogleAccount
  alias SMG.Events

  @doc """
  Fetches events from Google Calendar for a given account
  """
  def fetch_events(%GoogleAccount{} = google_account, opts \\ []) do
    with {:ok, conn} <- get_connection(google_account),
         {:ok, response} <- GoogleApi.Calendar.V3.Api.Events.calendar_events_list(conn, "primary", opts) do
      events = response.items || []
      {:ok, events}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Syncs calendar events from Google Calendar to our database
  """
  def sync_events(%GoogleAccount{} = google_account) do
    case fetch_events(google_account, time_min: DateTime.utc_now() |> DateTime.to_iso8601()) do
      {:ok, google_events} ->
        results = Enum.map(google_events, fn google_event ->
          sync_single_event(google_account, google_event)
        end)

        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates or updates a single calendar event in our database
  """
  def sync_single_event(%GoogleAccount{} = google_account, %Event{} = google_event) do
    event_params = %{
      google_event_id: google_event.id,
      title: google_event.summary,
      description: google_event.description,
      start_time: parse_datetime(google_event.start),
      end_time: parse_datetime(google_event.end),
      google_account_id: google_account.id
    }

    # Extract meeting link from description or location
    meeting_link = extract_meeting_link(google_event)
    event_params = if meeting_link, do: Map.put(event_params, :meeting_link, meeting_link), else: event_params

    case Events.get_event_by_google_id(google_event.id) do
      nil ->
        Events.create_event(event_params)

      existing_event ->
        Events.update_event(existing_event, event_params)
    end
  end

  defp get_connection(%GoogleAccount{access_token: token}) when is_binary(token) do
    conn = Connection.new(token)
    {:ok, conn}
  end

  defp get_connection(_), do: {:error, "No valid access token"}

  defp parse_datetime(%{date_time: dt}) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(%{date: date}) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00])
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp extract_meeting_link(%Event{description: description}) when is_binary(description) do
    SMG.Events.CalendarEvent.extract_meeting_link(description)
  end

  defp extract_meeting_link(%Event{location: location}) when is_binary(location) do
    SMG.Events.CalendarEvent.extract_meeting_link(location)
  end

  defp extract_meeting_link(_), do: nil
end