defmodule SMG.AI.EmailGenerator do
  @moduledoc """
  AI-powered email content generation based on meeting transcripts
  """

  alias SMG.Events.CalendarEvent
  alias SMG.Emails
  require Logger

  @doc """
  Generates email content from a meeting transcript for different email types
  """
  def generate_email_content(%CalendarEvent{} = event, email_type, recipient \\ nil) do
    user = get_user_from_event(event)

    if user do
      with {:ok, transcript} <- fetch_transcript(event) do
        case generate_content_for_email_type(transcript, event, email_type, recipient) do
          {:ok, {subject, body}} ->
            create_draft_email_content(event, subject, body, email_type, recipient, user)

          {:error, reason} ->
            {:error, reason}
        end
      else
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, "Could not find user for event"}
    end
  end

  @doc """
  Generates multiple email types for a meeting
  """
  def generate_multi_type_emails(%CalendarEvent{} = event, recipient \\ nil) do
    email_types = ["followup", "thank_you", "meeting_summary", "action_items"]

    Enum.map(email_types, fn email_type ->
      case generate_email_content(event, email_type, recipient) do
        {:ok, email_content} ->
          {email_type, {:ok, email_content}}

        {:error, reason} ->
          {email_type, {:error, reason}}
      end
    end)
  end

  defp fetch_transcript(%CalendarEvent{transcript_url: nil}) do
    {:error, "No transcript available"}
  end

  defp fetch_transcript(%CalendarEvent{transcript_url: url} = event) when is_binary(url) do
    Logger.info("Fetching transcript for email generation",
      event_id: event.id,
      url: String.slice(url, 0, 100) <> "..."
    )

    case Tesla.get(url) do
      {:ok, %{status: 200, body: body}} ->
        Logger.info("Successfully fetched transcript for email", event_id: event.id, size: byte_size(body))
        {:ok, body}

      {:ok, %{status: status}} ->
        Logger.warning("Failed to fetch transcript from Recall.ai for email",
          event_id: event.id,
          status: status
        )
        {:error, "Failed to fetch transcript: HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Network error fetching transcript for email",
          event_id: event.id,
          reason: inspect(reason)
        )
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp generate_content_for_email_type(transcript, event, email_type, recipient) do
    prompt = build_email_prompt(transcript, event, email_type, recipient)

    case call_openai(prompt) do
      {:ok, content} -> parse_email_content(content)
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_email_prompt(transcript, event, email_type, recipient) do
    email_guidance = get_email_guidance(email_type)
    recipient_context = if recipient, do: "Recipient: #{recipient[:name] || recipient[:email] || "Team member"}", else: "Recipient: Team member"

    """
    #{email_guidance}

    Meeting Title: #{event.title || "Meeting"}
    Meeting Date: #{format_date(event.start_time)}
    #{recipient_context}

    Transcript:
    #{String.slice(transcript, 0, 3500)}

    Guidelines:
    - Use a professional yet friendly tone
    - Be concise and actionable
    - Include specific details from the meeting
    - Avoid confidential or sensitive information
    - Make it personalized and relevant
    - Format as: SUBJECT: [subject line] | BODY: [email body]

    Generate the email:
    """
  end

  defp get_email_guidance(email_type) do
    case email_type do
      "followup" ->
        "Create a professional follow-up email that summarizes the meeting's key points and outlines next steps or action items. This should help maintain momentum after the meeting."

      "thank_you" ->
        "Create a warm thank-you email expressing appreciation for the meeting, highlighting valuable insights shared, and reinforcing positive relationships."

      "meeting_summary" ->
        "Create a comprehensive meeting summary email that captures the main discussion points, decisions made, and key takeaways for all participants."

      "action_items" ->
        "Create an action-oriented email that clearly lists tasks, responsibilities, deadlines, and next steps discussed during the meeting."

      "reminder" ->
        "Create a friendly reminder email about commitments, deadlines, or follow-up actions discussed in the meeting."

      "introduction" ->
        "Create an introduction email to connect meeting participants or introduce relevant contacts based on the meeting discussion."

      _ ->
        "Create a professional email based on the meeting content that serves the purpose of #{email_type}."
    end
  end

  defp parse_email_content(content) do
    case Regex.run(~r/SUBJECT:\s*(.+?)\s*\|\s*BODY:\s*(.+)/s, content) do
      [_, subject, body] ->
        {:ok, {String.trim(subject), String.trim(body)}}

      _ ->
        # Fallback: try to parse without the format
        lines = String.split(content, "\n", parts: 2, trim: true)
        case lines do
          [subject, body] ->
            {:ok, {String.trim(subject), String.trim(body)}}
          [single_line] ->
            {:ok, {"Follow-up from meeting", String.trim(single_line)}}
          _ ->
            {:error, "Could not parse email content format"}
        end
    end
  end

  defp call_openai(prompt) do
    case call_openai_with_retry(prompt, 3) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, "OpenAI API error: #{inspect(reason)}"}
    end
  end

  defp call_openai_with_retry(_prompt, 0) do
    {:error, :max_retries_exceeded}
  end

  defp call_openai_with_retry(prompt, retries_left) do
    case OpenAI.chat_completion(
           model: "gpt-4o-mini",
           messages: [
             %{
               role: "system",
               content:
                 "You are a professional business communications expert specializing in crafting effective follow-up emails and meeting summaries."
             },
             %{role: "user", content: prompt}
           ],
           max_tokens: 800,
           temperature: 0.7,
           stream: false
         ) do
      {:ok, response} ->
        content =
          response.choices
          |> List.first()
          |> Map.get("message")
          |> Map.get("content")
          |> String.trim()

        {:ok, content}

      {:error, :timeout} ->
        Logger.warning("OpenAI API timeout for email generation, retrying... (#{retries_left - 1} retries left)")
        Process.sleep(1000)
        call_openai_with_retry(prompt, retries_left - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_draft_email_content(event, subject, body, email_type, recipient, user) do
    recipient_email = if recipient, do: recipient[:email], else: nil
    recipient_name = if recipient, do: recipient[:name], else: nil

    Emails.create_email_content(%{
      subject: subject,
      body: body,
      email_type: email_type,
      status: "draft",
      generated_from_transcript: true,
      recipient_email: recipient_email,
      recipient_name: recipient_name,
      user_id: user.id,
      calendar_event_id: event.id
    })
  end

  defp get_user_from_event(%CalendarEvent{google_account: google_account} = event)
       when not is_nil(google_account) do
    case google_account do
      %{user: %Ecto.Association.NotLoaded{}} ->
        get_user_from_event(%{event | google_account: nil})

      %{user: user} when not is_nil(user) ->
        user

      _ ->
        get_user_from_event(%{event | google_account: nil})
    end
  end

  defp get_user_from_event(%CalendarEvent{google_account_id: google_account_id}) do
    case SMG.Accounts.get_google_account(google_account_id) do
      %{user_id: user_id} ->
        SMG.Accounts.get_user(user_id)

      _ ->
        nil
    end
  end

  defp get_user_from_event(_), do: nil

  defp format_date(nil), do: "Unknown"

  defp format_date(datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_string()
  end
end