defmodule SMG.AI.ContentGenerator do
  @moduledoc """
  AI-powered content generation for social media posts based on meeting transcripts
  """

  alias SMG.Events.CalendarEvent
  alias SMG.Social
  alias SMG.Accounts.User

  @doc """
  Generates social media content from a meeting transcript
  """
  def generate_social_content(%CalendarEvent{} = event) do
    with {:ok, transcript} <- fetch_transcript(event),
         {:ok, content} <- generate_content_from_transcript(transcript, event) do
      # Create a draft social post
      create_draft_social_post(event, content)
    else
      {:error, reason} ->
        {:error, "Failed to generate content: #{reason}"}
    end
  end

  @doc """
  Generates content suggestions for different social media platforms
  """
  def generate_multi_platform_content(%CalendarEvent{} = event) do
    with {:ok, transcript} <- fetch_transcript(event) do
      platforms = ["linkedin", "twitter"]

      Enum.map(platforms, fn platform ->
        case generate_content_for_platform(transcript, event, platform) do
          {:ok, content} ->
            {platform, content}

          {:error, reason} ->
            {platform, {:error, reason}}
        end
      end)
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_transcript(%CalendarEvent{transcript_url: nil}) do
    {:error, "No transcript available"}
  end

  defp fetch_transcript(%CalendarEvent{transcript_url: url}) when is_binary(url) do
    # In a real implementation, you would fetch the transcript from the URL
    # For now, we'll simulate this
    case Tesla.get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "Failed to fetch transcript: HTTP #{status}"}

      {:error, reason} ->
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp generate_content_from_transcript(transcript, event) do
    generate_content_for_platform(transcript, event, "linkedin")
  end

  defp generate_content_for_platform(transcript, event, platform) do
    prompt = build_prompt(transcript, event, platform)

    case call_openai(prompt) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_prompt(transcript, event, platform) do
    platform_guidance = case platform do
      "linkedin" ->
        "Create a professional LinkedIn post (150-200 words) suitable for business networking. Focus on insights, lessons learned, or valuable takeaways. Use a professional tone and include relevant hashtags."

      "twitter" ->
        "Create a Twitter thread (2-3 tweets, max 280 characters each) that captures the key insights. Use a conversational tone and include relevant hashtags."

      _ ->
        "Create an engaging social media post that highlights the key points and insights from this meeting."
    end

    """
    Based on the following meeting transcript, #{platform_guidance}

    Meeting Title: #{event.title || "Meeting"}
    Meeting Date: #{format_date(event.start_time)}

    Transcript:
    #{String.slice(transcript, 0, 3000)}

    Guidelines:
    - Focus on actionable insights or key takeaways
    - Maintain a positive and professional tone
    - Avoid mentioning sensitive or confidential information
    - Make it engaging and valuable for the audience
    - Include 2-3 relevant hashtags

    Generate the social media content:
    """
  end

  defp call_openai(prompt) do
    case OpenAI.chat_completion(
      model: "gpt-4o-mini",
      messages: [
        %{role: "system", content: "You are a professional social media content creator specializing in business and professional development content."},
        %{role: "user", content: prompt}
      ],
      max_tokens: 500,
      temperature: 0.7
    ) do
      {:ok, response} ->
        content = response.choices
                  |> List.first()
                  |> Map.get("message")
                  |> Map.get("content")
                  |> String.trim()

        {:ok, content}

      {:error, reason} ->
        {:error, "OpenAI API error: #{inspect(reason)}"}
    end
  end

  defp create_draft_social_post(event, content) do
    # Get the user through the google account
    user = get_user_from_event(event)

    if user do
      Social.create_social_post(%{
        content: content,
        platform: "linkedin",
        status: "draft",
        generated_from_transcript: true,
        user_id: user.id,
        calendar_event_id: event.id
      })
    else
      {:error, "Could not find user for event"}
    end
  end

  defp get_user_from_event(%CalendarEvent{google_account: %{user: user}}) do
    user
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