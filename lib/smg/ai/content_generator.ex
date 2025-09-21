defmodule SMG.AI.ContentGenerator do
  @moduledoc """
  AI-powered content generation for social media posts based on meeting transcripts
  """

  alias SMG.Events.CalendarEvent
  alias SMG.Social
  require Logger

  @doc """
  Generates social media content from a meeting transcript using user's automations
  """
  def generate_social_content(%CalendarEvent{} = event) do
    user = get_user_from_event(event)

    if user do
      # Get active automations for all platforms
      generate_content_for_all_automations(event, user)
    else
      {:error, "Could not find user for event"}
    end
  end

  @doc """
  Generates content suggestions for different social media platforms
  """
  def generate_multi_platform_content(%CalendarEvent{} = event) do
    with {:ok, transcript} <- fetch_transcript(event) do
      platforms = ["linkedin"]

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

  defp fetch_transcript(%CalendarEvent{transcript_url: url} = event) when is_binary(url) do
    Logger.info("Fetching transcript for event",
      event_id: event.id,
      url: String.slice(url, 0, 100) <> "..."
    )

    case Tesla.get(url) do
      {:ok, %{status: 200, body: body}} ->
        Logger.info("Successfully fetched transcript", event_id: event.id, size: byte_size(body))
        {:ok, body}

      {:ok, %{status: status}} ->
        Logger.warning("Failed to fetch transcript from Recall.ai",
          event_id: event.id,
          status: status,
          url_prefix: String.slice(url, 0, 100) <> "..."
        )

        {:error, "Failed to fetch transcript: HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Network error fetching transcript",
          event_id: event.id,
          reason: inspect(reason)
        )

        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp generate_content_for_all_automations(event, user) do
    with {:ok, transcript} <- fetch_transcript(event) do
      # Get all enabled automations for the user
      all_automations = SMG.Settings.list_automations(user)
      enabled_automations = Enum.filter(all_automations, & &1.enabled)

      if length(enabled_automations) > 0 do
        # Generate content for each automation
        results =
          Enum.map(enabled_automations, fn automation ->
            generate_content_for_automation(transcript, event, automation)
          end)

        # Filter successful results
        successful_results = Enum.filter(results, fn {status, _} -> status == :ok end)

        if length(successful_results) > 0 do
          {:ok, successful_results}
        else
          {:error, "Failed to generate content for any automation"}
        end
      else
        # Fall back to default content generation
        generate_default_content(transcript, event, user)
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_content_for_automation(transcript, event, automation) do
    prompt = build_automation_prompt(transcript, event, automation)

    case call_openai(prompt) do
      {:ok, content} ->
        case create_draft_social_post(event, content, automation.platform) do
          {:ok, social_post} ->
            # Automatically post if automation has auto_publish enabled
            if automation.auto_publish do
              case SMG.Services.SocialMediaPoster.post_to_platform(social_post) do
                {:ok, posted_social_post} ->
                  {:ok, posted_social_post}

                {:error, posting_reason} ->
                  # Log the posting failure but still return the draft post
                  require Logger

                  Logger.warning("Failed to auto-post content from automation",
                    automation_id: automation.id,
                    platform: automation.platform,
                    reason: posting_reason
                  )

                  {:ok, social_post}
              end
            else
              {:ok, social_post}
            end

          {:error, reason} ->
            {:error, "Failed to create post: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_default_content(transcript, event, _user) do
    # Create default LinkedIn post if no automations exist
    prompt = build_prompt(transcript, event, "linkedin")

    case call_openai(prompt) do
      {:ok, content} ->
        create_draft_social_post(event, content, "linkedin")

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_content_for_platform(transcript, event, platform) do
    prompt = build_prompt(transcript, event, platform)

    case call_openai(prompt) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_automation_prompt(transcript, event, automation) do
    base_prompt =
      if automation.prompt_template && String.length(automation.prompt_template) > 0 do
        # Use custom template with placeholder replacement
        automation.prompt_template
        |> String.replace("{content_type}", automation.content_type)
        |> String.replace("{platform}", automation.platform)
        |> String.replace("{meeting_title}", event.title || "Meeting")
      else
        # Use default template
        build_default_automation_prompt(automation)
      end

    """
    #{base_prompt}

    Meeting Title: #{event.title || "Meeting"}
    Meeting Date: #{format_date(event.start_time)}

    Transcript:
    #{String.slice(transcript, 0, 3000)}

    Guidelines:
    - Focus on #{automation.content_type} content
    - Optimize for #{automation.platform} platform
    - Maintain a professional tone
    - Avoid mentioning sensitive or confidential information
    - Make it engaging and valuable for the audience
    - Include 2-3 relevant hashtags

    Generate the social media content:
    """
  end

  defp build_default_automation_prompt(automation) do
    case automation.content_type do
      "marketing" ->
        "Create engaging marketing content for #{automation.platform} that highlights the business value and key insights from this meeting transcript."

      "educational" ->
        "Create educational content for #{automation.platform} that teaches the audience about the key concepts and learnings from this meeting."

      "insights" ->
        "Create insightful content for #{automation.platform} that shares the key takeaways and strategic insights from this meeting."

      "summary" ->
        "Create a professional summary for #{automation.platform} that captures the main points and outcomes of this meeting."

      "takeaways" ->
        "Create content for #{automation.platform} that focuses on actionable takeaways and next steps from this meeting."

      _ ->
        "Create engaging #{automation.content_type} content for #{automation.platform} based on this meeting transcript."
    end
  end

  defp build_prompt(transcript, event, platform) do
    platform_guidance =
      case platform do
        "linkedin" ->
          "Create a professional LinkedIn post (150-200 words) suitable for business networking. Focus on insights, lessons learned, or valuable takeaways. Use a professional tone and include relevant hashtags."

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
                 "You are a professional social media content creator specializing in business and professional development content."
             },
             %{role: "user", content: prompt}
           ],
           max_tokens: 500,
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
        Logger.warning("OpenAI API timeout, retrying... (#{retries_left - 1} retries left)")
        Process.sleep(1000)
        call_openai_with_retry(prompt, retries_left - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_draft_social_post(event, content, platform \\ "linkedin") do
    # Get the user through the google account
    user = get_user_from_event(event)

    if user do
      Social.create_social_post(%{
        content: content,
        platform: platform,
        status: "draft",
        generated_from_transcript: true,
        user_id: user.id,
        calendar_event_id: event.id
      })
    else
      {:error, "Could not find user for event"}
    end
  end

  defp get_user_from_event(%CalendarEvent{google_account: google_account} = event)
       when not is_nil(google_account) do
    case google_account do
      %{user: %Ecto.Association.NotLoaded{}} ->
        # User association not loaded, fallback to loading by ID
        get_user_from_event(%{event | google_account: nil})

      %{user: user} when not is_nil(user) ->
        user

      _ ->
        # Fallback to loading by google_account_id
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
