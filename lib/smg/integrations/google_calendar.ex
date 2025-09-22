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
    fetch_events_with_retry(google_account, opts, false)
  end

  defp fetch_events_with_retry(%GoogleAccount{} = google_account, opts, retried?) do
    require Logger

    Logger.info("Starting to fetch events from Google Calendar",
      account_id: google_account.id,
      email: google_account.email,
      opts: opts,
      retried: retried?
    )

    with {:ok, conn} <- get_connection(google_account) do
      Logger.info("Successfully created Google API connection", account_id: google_account.id)

      case GoogleApi.Calendar.V3.Api.Events.calendar_events_list(conn, "primary", opts) do
        {:ok, response} ->
          events = response.items || []

          Logger.info("Successfully fetched events from Google Calendar",
            account_id: google_account.id,
            event_count: length(events)
          )

          # Log each event for debugging
          Enum.each(events, fn event ->
            start_time =
              case event.start do
                %{dateTime: dt} -> dt
                %{date: date} -> date
                _ -> nil
              end

            end_time =
              case event.end do
                %{dateTime: dt} -> dt
                %{date: date} -> date
                _ -> nil
              end

            Logger.info("Calendar Event",
              event_id: event.id,
              title: event.summary,
              start_time: start_time,
              end_time: end_time,
              description:
                if(event.description,
                  do: String.slice(event.description, 0, 100) <> "...",
                  else: nil
                ),
              attendees_count: if(event.attendees, do: length(event.attendees), else: 0)
            )
          end)

          {:ok, events}

        {:error, %Tesla.Env{} = response} ->
          Logger.error("Google Calendar API returned error response",
            account_id: google_account.id,
            status: response.status,
            body: response.body
          )

          # Check if this is a token expiry error and we haven't retried yet
          if is_token_expired_error?(response) and not retried? do
            Logger.info("Token expired, attempting to refresh and retry",
              account_id: google_account.id
            )

            case refresh_token_and_retry(google_account, opts) do
              {:ok, events} -> {:ok, events}
              {:error, reason} -> {:error, reason}
            end
          else
            {:error, "Google Calendar API error (#{response.status}): #{response.body}"}
          end

        {:error, reason} ->
          Logger.error("Failed to fetch events from Google Calendar",
            account_id: google_account.id,
            error: inspect(reason, limit: :infinity)
          )

          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("Failed to create Google API connection",
          account_id: google_account.id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Syncs calendar events from Google Calendar to our database
  """
  def sync_events(%GoogleAccount{} = google_account) do
    require Logger

    Logger.info("Starting calendar sync",
      account_id: google_account.id,
      email: google_account.email
    )

    # Fetch events from 30 days ago to 30 days in the future to get both past and upcoming events
    start_time = DateTime.utc_now() |> DateTime.add(-30, :day) |> DateTime.to_iso8601()
    end_time = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.to_iso8601()

    case fetch_events(google_account, time_min: start_time, time_max: end_time, max_results: 100) do
      {:ok, google_events} ->
        Logger.info("Fetched events from Google, now syncing to database",
          account_id: google_account.id,
          event_count: length(google_events)
        )

        results =
          Enum.map(google_events, fn google_event ->
            sync_single_event(google_account, google_event)
          end)

        Logger.info("Calendar sync completed",
          account_id: google_account.id,
          synced_count: length(results)
        )

        {:ok, results}

      {:error, %Tesla.Env{} = response} ->
        error_message = extract_error_message(response)
        {:error, error_message}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_error_message(%Tesla.Env{status: status, body: body}) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} ->
        "Google Calendar API error (#{status}): #{message}"

      {:ok, %{"error" => %{"errors" => [%{"message" => message} | _]}}} ->
        "Google Calendar API error (#{status}): #{message}"

      _ ->
        "Google Calendar API error (#{status}): #{body}"
    end
  end

  defp extract_error_message(reason) when is_binary(reason) do
    reason
  end

  defp extract_error_message(reason) do
    "Unknown error: #{inspect(reason)}"
  end

  @doc """
  Creates or updates a single calendar event in our database
  """
  def sync_single_event(%GoogleAccount{} = google_account, %Event{} = google_event) do
    require Logger

    # Extract meeting link from multiple sources
    meeting_link = extract_meeting_link_from_multiple_sources(google_event)

    # Build comprehensive description with additional info
    enhanced_description = build_enhanced_description(google_event)

    # Extract attendee information
    {attendee_count, attendee_emails} = extract_attendee_data(google_event.attendees)

    event_params = %{
      google_event_id: google_event.id,
      title: google_event.summary,
      description: enhanced_description,
      start_time: parse_datetime(google_event.start),
      end_time: parse_datetime(google_event.end),
      meeting_link: meeting_link,
      google_account_id: google_account.id,
      attendee_count: attendee_count,
      attendee_emails: attendee_emails
    }

    case Events.get_event_by_google_id(google_event.id) do
      nil ->
        Logger.info("Creating new calendar event",
          event_id: google_event.id,
          title: google_event.summary,
          start_time: parse_datetime(google_event.start),
          has_meeting_link: not is_nil(meeting_link)
        )

        Events.create_event(event_params)

      existing_event ->
        Logger.info("Updating existing calendar event",
          event_id: google_event.id,
          title: google_event.summary,
          start_time: parse_datetime(google_event.start),
          has_meeting_link: not is_nil(meeting_link)
        )

        Events.update_event(existing_event, event_params)
    end
  end

  defp get_connection(%GoogleAccount{access_token: token}) when is_binary(token) do
    require Logger

    Logger.info("Creating Google API connection",
      token_length: String.length(token),
      token_preview: String.slice(token, 0, 20) <> "..."
    )

    conn = Connection.new(token)
    {:ok, conn}
  end

  defp get_connection(account) do
    require Logger

    Logger.error("No valid access token found",
      account_id: account.id,
      has_token: not is_nil(account.access_token),
      token_type: if(account.access_token, do: "binary", else: "nil")
    )

    {:error, "No valid access token"}
  end

  # Handle GoogleApi.Calendar.V3.Model.EventDateTime structs
  defp parse_datetime(%GoogleApi.Calendar.V3.Model.EventDateTime{dateTime: dt})
       when not is_nil(dt) do
    # The dateTime field is already a DateTime struct, just convert to UTC
    case DateTime.shift_zone(dt, "Etc/UTC") do
      {:ok, utc_datetime} -> utc_datetime
      # Fallback to original if shift fails
      {:error, _} -> dt
    end
  end

  defp parse_datetime(%GoogleApi.Calendar.V3.Model.EventDateTime{date: date})
       when not is_nil(date) do
    # For all-day events, the date field is a Date struct
    # Convert to start of day in UTC
    case DateTime.new(date, ~T[00:00:00], "Etc/UTC") do
      {:ok, datetime} -> datetime
      # Fallback
      {:error, _} -> DateTime.new!(date, ~T[00:00:00])
    end
  end

  # Legacy support for map-based datetime (in case some events still come as maps)
  defp parse_datetime(%{dateTime: dt}) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _} ->
        case DateTime.shift_zone(datetime, "Etc/UTC") do
          {:ok, utc_datetime} -> utc_datetime
          # Fallback to original if shift fails
          {:error, _} -> datetime
        end

      _ ->
        nil
    end
  end

  defp parse_datetime(%{date: date}) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, date} ->
        case DateTime.new(date, ~T[00:00:00], "Etc/UTC") do
          {:ok, datetime} -> datetime
          # Fallback
          {:error, _} -> DateTime.new!(date, ~T[00:00:00])
        end

      _ ->
        nil
    end
  end

  defp parse_datetime(datetime_struct) do
    require Logger

    Logger.error("Failed to parse datetime",
      struct: inspect(datetime_struct, limit: :infinity, pretty: true),
      keys: if(is_map(datetime_struct), do: Map.keys(datetime_struct), else: "not a map"),
      struct_type:
        if(is_map(datetime_struct), do: datetime_struct.__struct__, else: "not a struct")
    )

    nil
  end

  defp extract_meeting_link_from_multiple_sources(%Event{} = google_event) do
    # Check hangoutLink first (Google Meet links)
    cond do
      google_event.hangoutLink && String.length(google_event.hangoutLink) > 0 ->
        google_event.hangoutLink

      # Check conference data for meeting links
      google_event.conferenceData && google_event.conferenceData.entryPoints ->
        extract_meeting_from_conference_data(google_event.conferenceData.entryPoints)

      # Check description for meeting links
      google_event.description ->
        SMG.Events.CalendarEvent.extract_meeting_link(google_event.description)

      # Check location for meeting links
      google_event.location ->
        SMG.Events.CalendarEvent.extract_meeting_link(google_event.location)

      true ->
        nil
    end
  end

  defp extract_meeting_from_conference_data(entry_points) when is_list(entry_points) do
    entry_points
    |> Enum.find(fn entry_point ->
      entry_point.entryPointType == "video" && entry_point.uri
    end)
    |> case do
      %{uri: uri} when is_binary(uri) -> uri
      _ -> nil
    end
  end

  defp extract_meeting_from_conference_data(_), do: nil

  defp build_enhanced_description(%Event{} = google_event) do
    base_description = google_event.description || ""

    additional_info =
      []
      |> add_info_if_present("Location", google_event.location)
      |> add_info_if_present("Status", google_event.status)
      |> add_info_if_present("Event Type", google_event.eventType)
      |> add_info_if_present("Visibility", google_event.visibility)
      |> add_attendees_info(google_event.attendees)
      |> add_creator_info(google_event.creator, google_event.organizer)
      |> add_conference_info(google_event.conferenceData)

    case additional_info do
      [] ->
        base_description

      info_list ->
        info_text = Enum.join(info_list, "\n")

        if String.length(base_description) > 0 do
          "#{base_description}\n\n--- Additional Info ---\n#{info_text}"
        else
          info_text
        end
    end
  end

  defp add_info_if_present(list, label, value) when is_binary(value) and value != "" do
    [list | ["#{label}: #{value}"]]
  end

  defp add_info_if_present(list, _label, _value), do: list

  defp add_attendees_info(list, nil), do: list

  defp add_attendees_info(list, attendees) when is_list(attendees) do
    attendee_count = length(attendees)

    attendee_emails =
      attendees
      |> Enum.map(fn attendee -> attendee.email end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.join(", ")

    attendee_info = "Attendees (#{attendee_count}): #{attendee_emails}"
    [list | [attendee_info]]
  end

  defp add_attendees_info(list, _), do: list

  defp extract_attendee_data(nil), do: {0, []}

  defp extract_attendee_data(attendees) when is_list(attendees) do
    attendee_emails =
      attendees
      |> Enum.map(fn attendee -> attendee.email end)
      |> Enum.filter(&(&1 != nil))

    {length(attendees), attendee_emails}
  end

  defp extract_attendee_data(_), do: {0, []}

  defp add_creator_info(list, creator, organizer) do
    creator_info =
      []
      |> add_creator_detail("Creator", creator)
      |> add_creator_detail("Organizer", organizer)

    case creator_info do
      [] -> list
      info -> [list | info]
    end
  end

  defp add_creator_detail(list, label, person) when is_map(person) do
    email = person.email
    name = person.displayName

    cond do
      email && name -> [list | ["#{label}: #{name} (#{email})"]]
      email -> [list | ["#{label}: #{email}"]]
      name -> [list | ["#{label}: #{name}"]]
      true -> list
    end
  end

  defp add_creator_detail(list, _label, _person), do: list

  defp add_conference_info(list, nil), do: list

  defp add_conference_info(list, conference_data) when is_map(conference_data) do
    conference_info =
      []
      |> add_conference_detail("Conference ID", conference_data.conferenceId)
      |> add_conference_detail(
        "Conference Solution",
        get_conference_solution_name(conference_data.conferenceSolution)
      )

    case conference_info do
      [] -> list
      info -> [list | info]
    end
  end

  defp add_conference_info(list, _), do: list

  defp get_conference_solution_name(nil), do: nil

  defp get_conference_solution_name(conference_solution) when is_map(conference_solution) do
    conference_solution.name
  end

  defp get_conference_solution_name(_), do: nil

  defp add_conference_detail(list, _label, nil), do: list
  defp add_conference_detail(list, _label, ""), do: list

  defp add_conference_detail(list, label, value) when is_binary(value) do
    [list | ["#{label}: #{value}"]]
  end

  defp add_conference_detail(list, _label, _value), do: list

  @doc """
  Checks if the API error response indicates an expired OAuth token
  """
  defp is_token_expired_error?(%Tesla.Env{status: 401}), do: true
  defp is_token_expired_error?(%Tesla.Env{status: 403, body: body}) do
    # Check for specific Google OAuth error messages
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} ->
        String.contains?(String.downcase(message), ["invalid credentials", "token expired", "invalid_token"])

      {:ok, %{"error" => %{"errors" => errors}}} when is_list(errors) ->
        Enum.any?(errors, fn error ->
          message = error["message"] || ""
          String.contains?(String.downcase(message), ["invalid credentials", "token expired", "invalid_token"])
        end)

      _ -> false
    end
  end
  defp is_token_expired_error?(_), do: false

  @doc """
  Attempts to refresh the token and retry the calendar sync
  """
  defp refresh_token_and_retry(%GoogleAccount{} = google_account, opts) do
    require Logger

    Logger.info("Attempting to refresh Google OAuth token",
      account_id: google_account.id,
      email: google_account.email
    )

    case SMG.Integrations.GoogleAuth.refresh_token(google_account.refresh_token) do
      {:ok, token_data} ->
        # Update the account with new token
        update_attrs = %{
          access_token: token_data["access_token"],
          expires_at: DateTime.add(DateTime.utc_now(), token_data["expires_in"], :second)
        }

        # Add new refresh token if provided
        update_attrs =
          if token_data["refresh_token"] do
            Map.put(update_attrs, :refresh_token, token_data["refresh_token"])
          else
            update_attrs
          end

        case SMG.Accounts.update_google_account(google_account, update_attrs) do
          {:ok, updated_account} ->
            Logger.info("Successfully refreshed token, retrying calendar sync",
              account_id: google_account.id,
              new_expires_at: updated_account.expires_at
            )

            # Retry the fetch with the updated account
            fetch_events_with_retry(updated_account, opts, true)

          {:error, changeset} ->
            Logger.error("Failed to update account with refreshed token",
              account_id: google_account.id,
              errors: inspect(changeset.errors)
            )

            {:error, "Failed to update account with new token"}
        end

      {:error, reason} ->
        Logger.error("Failed to refresh Google OAuth token",
          account_id: google_account.id,
          reason: reason
        )

        {:error, "Token refresh failed: #{reason}"}
    end
  end
end
