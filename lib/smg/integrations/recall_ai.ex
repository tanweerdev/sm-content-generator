defmodule SMG.Integrations.RecallAI do
  @moduledoc """
  Recall.ai API integration for meeting transcription
  """

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://us-west-2.recall.ai"
  plug Tesla.Middleware.Headers, [{"Authorization", "Token #{api_token()}"}]
  plug Tesla.Middleware.JSON

  alias SMG.Events.CalendarEvent

  @doc """
  Creates a bot to join a meeting
  """
  def create_bot(meeting_url, _event_title \\ "Meeting") do
    require Logger

    body = %{
      meeting_url: meeting_url,
      recording_config: %{
        transcript: %{
          provider: %{
            recallai_streaming: %{
              mode: "prioritize_low_latency",
              language_code: "en"
            }
          }
        }
      }
    }

    Logger.info("Creating Recall.ai bot", meeting_url: meeting_url, body: body)

    case post("/api/v1/bot", body) do
      {:ok, %{status: 201, body: response}} ->
        Logger.info("Bot created successfully", bot_id: response["id"])
        {:ok, response}

      {:ok, %{status: status, body: error}} ->
        Logger.error("Failed to create bot", status: status, error: error)
        {:error, "Failed to create bot: #{status} - #{inspect(error)}"}

      {:error, reason} ->
        Logger.error("API request failed", reason: reason)
        {:error, "API request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Gets bot status and information
  """
  def get_bot(bot_id) do
    case get("/api/v1/bot/#{bot_id}") do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %{status: status, body: error}} ->
        {:error, "Failed to get bot: #{status} - #{inspect(error)}"}

      {:error, reason} ->
        {:error, "API request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Deletes a bot
  """
  def delete_bot(bot_id) do
    case delete("/api/v1/bot/#{bot_id}") do
      {:ok, %{status: 204}} ->
        {:ok, :deleted}

      {:ok, %{status: status, body: error}} ->
        {:error, "Failed to delete bot: #{status} - #{inspect(error)}"}

      {:error, reason} ->
        {:error, "API request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Schedules a bot for a calendar event
  """
  def schedule_bot_for_event(%CalendarEvent{} = event) do
    if event.meeting_link && event.notetaker_enabled do
      case create_bot(event.meeting_link, event.title || "Meeting") do
        {:ok, bot_response} ->
          SMG.Events.update_event(event, %{
            recall_bot_id: bot_response["id"],
            transcript_status: "scheduled"
          })

        {:error, reason} ->
          SMG.Events.update_event(event, %{transcript_status: "failed"})
          {:error, reason}
      end
    else
      {:error, "Event missing meeting link or notetaker not enabled"}
    end
  end

  @doc """
  Processes webhook from Recall.ai
  """
  def process_webhook(params) do
    case params["event"] do
      "bot.transcription_completed" ->
        bot_id = params["data"]["bot_id"]
        transcript_url = params["data"]["transcript_url"]

        # Find the calendar event with this bot_id
        case SMG.Events.get_event_by_recall_bot_id(bot_id) do
          nil ->
            {:error, "Event not found for bot_id: #{bot_id}"}

          event ->
            SMG.Events.update_event(event, %{
              transcript_url: transcript_url,
              transcript_status: "completed"
            })

            # Trigger AI content generation
            SMG.AI.ContentGenerator.generate_social_content(event)

            {:ok, "Processed transcription completion"}
        end

      "bot.meeting_ended" ->
        {:ok, "Meeting ended"}

      _ ->
        {:ok, "Unknown event type"}
    end
  end

  defp api_token do
    System.get_env("RECALL_AI_API_TOKEN") || raise "RECALL_AI_API_TOKEN not set"
  end
end
