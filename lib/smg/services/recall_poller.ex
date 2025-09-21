defmodule SMG.Services.RecallPoller do
  @moduledoc """
  GenServer that polls Recall.ai API to check for bot status updates
  Since we're using a shared account, we can't rely on webhooks
  """

  use GenServer
  require Logger
  import Ecto.Query

  alias SMG.{Events, Repo}
  alias SMG.Integrations.RecallAI
  alias SMG.Events.CalendarEvent

  # Poll every 30 seconds
  @poll_interval 30_000
  @max_retries 3

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule the first poll
    schedule_poll()
    {:ok, %{retry_count: 0}}
  end

  @impl true
  def handle_info(:poll_bots, state) do
    Logger.info("Starting bot status polling cycle")

    case poll_active_bots() do
      {:ok, processed_count} ->
        Logger.info("Bot polling completed successfully", processed: processed_count)
        schedule_poll()
        {:noreply, %{state | retry_count: 0}}

      {:error, reason} ->
        retry_count = state.retry_count + 1

        Logger.error("Bot polling failed",
          reason: reason,
          retry_count: retry_count,
          max_retries: @max_retries
        )

        if retry_count < @max_retries do
          # Retry with backoff
          Process.send_after(self(), :poll_bots, 5_000 * retry_count)
          {:noreply, %{state | retry_count: retry_count}}
        else
          # Reset retry count and schedule next regular poll
          Logger.error("Max retries reached, skipping this polling cycle")
          schedule_poll()
          {:noreply, %{state | retry_count: 0}}
        end
    end
  end

  @impl true
  def handle_call(:force_poll, _from, state) do
    case poll_active_bots() do
      {:ok, processed_count} ->
        {:reply, {:ok, processed_count}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def force_poll do
    GenServer.call(__MODULE__, :force_poll)
  end

  defp schedule_poll do
    Process.send_after(self(), :poll_bots, @poll_interval)
  end

  defp poll_active_bots do
    try do
      # Get all events with active recall bots
      active_events = get_events_with_active_bots()

      Logger.info("Found events with active bots", count: length(active_events))

      processed_count =
        active_events
        |> Enum.map(&check_bot_status/1)
        |> Enum.count(fn result ->
          case result do
            {:ok, _} -> true
            _ -> false
          end
        end)

      {:ok, processed_count}
    rescue
      error ->
        Logger.error("Error during bot polling", error: inspect(error))
        {:error, "Polling failed: #{inspect(error)}"}
    end
  end

  defp get_events_with_active_bots do
    from(e in CalendarEvent,
      where: not is_nil(e.recall_bot_id) and e.transcript_status in ["scheduled", "recording"],
      preload: [:google_account]
    )
    |> Repo.all()
  end

  defp check_bot_status(%CalendarEvent{recall_bot_id: bot_id} = event) do
    Logger.debug("Checking bot status", bot_id: bot_id, event_id: event.id)

    case RecallAI.get_bot(bot_id) do
      {:ok, bot_data} ->
        Logger.info("Successfully retrieved bot data",
          bot_id: bot_id,
          event_id: event.id,
          bot_data_keys: Map.keys(bot_data)
        )

        process_bot_status_update(event, bot_data)

      {:error, reason} ->
        Logger.error("Failed to get bot status from Recall.ai API",
          bot_id: bot_id,
          event_id: event.id,
          reason: inspect(reason, limit: :infinity),
          error_details: reason
        )

        {:error, reason}
    end
  end

  defp process_bot_status_update(event, bot_data) do
    # Safely extract status with better error handling
    status =
      case bot_data do
        %{"status_changes" => status_changes}
        when is_list(status_changes) and length(status_changes) > 0 ->
          case List.last(status_changes) do
            %{"code" => code} -> code
            _ -> nil
          end

        %{"status" => status} ->
          status

        _ ->
          nil
      end

    Logger.debug("Processing bot status update",
      bot_id: event.recall_bot_id,
      event_id: event.id,
      status: status,
      available_keys: Map.keys(bot_data),
      status_changes_present: Map.has_key?(bot_data, "status_changes"),
      status_present: Map.has_key?(bot_data, "status")
    )

    case status do
      "call_ended" ->
        handle_call_ended(event, bot_data)

      "transcription_completed" ->
        handle_transcription_completed(event, bot_data)

      "done" ->
        # Bot is completely done, including transcription
        handle_bot_completed(event, bot_data)

      "recording_done" ->
        # Recording is done, transcript might be available
        handle_recording_completed(event, bot_data)

      "error" ->
        handle_bot_error(event, bot_data)

      nil ->
        Logger.warning("No valid status found in bot data",
          bot_id: event.recall_bot_id,
          event_id: event.id,
          bot_data: bot_data
        )

        {:ok, :no_status}

      _ ->
        Logger.info("Bot status not actionable yet",
          bot_id: event.recall_bot_id,
          event_id: event.id,
          status: status
        )

        {:ok, :no_change}
    end
  end

  defp handle_call_ended(event, _bot_data) do
    Logger.info("Call ended for bot",
      bot_id: event.recall_bot_id,
      event_id: event.id
    )

    case Events.update_event(event, %{transcript_status: "processing"}) do
      {:ok, updated_event} ->
        {:ok, {:call_ended, updated_event}}

      {:error, changeset} ->
        {:error, "Failed to update event status: #{inspect(changeset)}"}
    end
  end

  defp handle_transcription_completed(event, bot_data) do
    transcript_url = extract_transcript_url(bot_data)

    Logger.info("Transcription completed for bot",
      bot_id: event.recall_bot_id,
      event_id: event.id,
      has_transcript_url: not is_nil(transcript_url)
    )

    update_attrs = %{
      transcript_status: "completed",
      transcript_url: transcript_url
    }

    case Events.update_event(event, update_attrs) do
      {:ok, updated_event} ->
        # Trigger AI content generation
        Task.start(fn ->
          case SMG.AI.ContentGenerator.generate_social_content(updated_event) do
            {:ok, _} ->
              Logger.info("AI content generation triggered", event_id: updated_event.id)

            {:error, reason} ->
              Logger.error("AI content generation failed",
                event_id: updated_event.id,
                reason: reason
              )
          end
        end)

        {:ok, {:transcription_completed, updated_event}}

      {:error, changeset} ->
        {:error, "Failed to update event: #{inspect(changeset)}"}
    end
  end

  defp handle_bot_error(event, bot_data) do
    error_message = extract_error_message(bot_data)

    Logger.error("Bot error detected",
      bot_id: event.recall_bot_id,
      event_id: event.id,
      error: error_message
    )

    case Events.update_event(event, %{transcript_status: "failed"}) do
      {:ok, updated_event} ->
        {:ok, {:error, updated_event}}

      {:error, changeset} ->
        {:error, "Failed to update event status: #{inspect(changeset)}"}
    end
  end

  defp extract_transcript_url(bot_data) do
    # Try to extract transcript URL from various places in the bot data
    cond do
      # New format: look in recordings -> media_shortcuts -> transcript -> data -> download_url
      transcript_url = get_in(bot_data, ["recordings"]) |> extract_from_recordings() ->
        transcript_url

      transcript_url = get_in(bot_data, ["recording", "transcript_url"]) ->
        transcript_url

      transcript_url = get_in(bot_data, ["transcript_url"]) ->
        transcript_url

      # Look for media files
      media_files = get_in(bot_data, ["media"]) ->
        media_files
        |> Enum.find(fn file -> file["type"] == "transcript" end)
        |> case do
          %{"url" => url} -> url
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp extract_from_recordings(recordings) when is_list(recordings) and length(recordings) > 0 do
    recordings
    |> List.first()
    |> get_in(["media_shortcuts", "transcript", "data", "download_url"])
  end

  defp extract_from_recordings(_), do: nil

  defp handle_bot_completed(event, bot_data) do
    transcript_url = extract_transcript_url(bot_data)

    Logger.info("Bot completed for event",
      bot_id: event.recall_bot_id,
      event_id: event.id,
      has_transcript_url: not is_nil(transcript_url)
    )

    update_attrs = %{
      transcript_status: "completed",
      transcript_url: transcript_url
    }

    case Events.update_event(event, update_attrs) do
      {:ok, updated_event} ->
        # Trigger AI content generation
        Task.start(fn ->
          case SMG.AI.ContentGenerator.generate_social_content(updated_event) do
            {:ok, _} ->
              Logger.info("AI content generation triggered", event_id: updated_event.id)

            {:error, reason} ->
              Logger.error("AI content generation failed",
                event_id: updated_event.id,
                reason: reason
              )
          end
        end)

        {:ok, {:bot_completed, updated_event}}

      {:error, changeset} ->
        {:error, "Failed to update event: #{inspect(changeset)}"}
    end
  end

  defp handle_recording_completed(event, bot_data) do
    transcript_url = extract_transcript_url(bot_data)

    Logger.info("Recording completed for bot",
      bot_id: event.recall_bot_id,
      event_id: event.id,
      has_transcript_url: not is_nil(transcript_url)
    )

    if transcript_url do
      # If transcript is already available, treat it like completion
      handle_bot_completed(event, bot_data)
    else
      # Recording is done but transcript not ready yet, update status to processing
      case Events.update_event(event, %{transcript_status: "processing"}) do
        {:ok, updated_event} ->
          {:ok, {:recording_completed, updated_event}}

        {:error, changeset} ->
          {:error, "Failed to update event status: #{inspect(changeset)}"}
      end
    end
  end

  defp extract_error_message(bot_data) do
    cond do
      error = get_in(bot_data, ["status_changes"]) |> List.last() |> Map.get("message") ->
        error

      error = get_in(bot_data, ["error", "message"]) ->
        error

      true ->
        "Unknown error"
    end
  end
end
