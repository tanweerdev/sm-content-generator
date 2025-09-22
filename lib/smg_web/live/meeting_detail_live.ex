defmodule SMGWeb.MeetingDetailLive do
  use SMGWeb, :live_view
  import Ecto.Query

  alias SMG.{Events, AI.ContentGenerator}
  alias SMG.Integrations.RecallAI

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    meeting = get_meeting_for_user!(id, user)

    socket =
      socket
      |> assign(:meeting, meeting)
      |> assign(:user, user)
      |> assign(:active_tab, "overview")
      |> assign(:generating_content, false)
      |> assign(:generating_email, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"tab" => tab}, _url, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: "/meetings/#{socket.assigns.meeting.id}?tab=#{tab}")}
  end

  @impl true
  def handle_event("generate_social_content", _params, socket) do
    meeting = socket.assigns.meeting

    socket = assign(socket, :generating_content, true)

    Task.start(fn ->
      case ContentGenerator.generate_multi_platform_content(meeting) do
        results when is_list(results) ->
          send(self(), {:content_generated, results})

        {:error, reason} ->
          send(self(), {:content_generation_failed, reason})
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("generate_follow_up_email", _params, socket) do
    meeting = socket.assigns.meeting

    socket = assign(socket, :generating_email, true)

    Task.start(fn ->
      case generate_follow_up_email(meeting) do
        {:ok, email_content} ->
          send(self(), {:email_generated, email_content})

        {:error, reason} ->
          send(self(), {:email_generation_failed, reason})
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("download_transcript", _params, socket) do
    meeting = socket.assigns.meeting

    if meeting.transcript_url do
      {:noreply, redirect(socket, external: meeting.transcript_url)}
    else
      socket =
        socket
        |> put_flash(:error, "Transcript not available")

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("deploy_bot", _params, socket) do
    meeting = socket.assigns.meeting

    if meeting.meeting_link do
      # First enable notetaker if not already enabled
      updated_meeting =
        if !meeting.notetaker_enabled do
          case Events.update_event(meeting, %{notetaker_enabled: true}) do
            {:ok, updated} -> updated
            {:error, _} -> meeting
          end
        else
          meeting
        end

      case RecallAI.schedule_bot_for_event(updated_meeting) do
        {:ok, _updated_event} ->
          socket =
            socket
            |> put_flash(
              :info,
              "Bot deployed successfully! It will join the meeting and start transcribing."
            )
            |> reload_meeting()

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> put_flash(:error, "Failed to deploy bot: #{reason}")

          {:noreply, socket}
      end
    else
      socket =
        socket
        |> put_flash(:error, "No meeting link found. Cannot deploy bot.")

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("check_bot_status", _params, socket) do
    meeting = socket.assigns.meeting

    if meeting.recall_bot_id do
      case RecallAI.get_bot(meeting.recall_bot_id) do
        {:ok, bot_data} ->
          socket =
            socket
            |> put_flash(:info, "Bot status: #{bot_data["status"]}")

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> put_flash(:error, "Failed to check bot status: #{reason}")

          {:noreply, socket}
      end
    else
      socket =
        socket
        |> put_flash(:error, "No bot deployed for this meeting.")

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:content_generated, _results}, socket) do
    socket =
      socket
      |> assign(:generating_content, false)
      |> put_flash(:info, "Social media content generated successfully!")
      |> reload_meeting()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:content_generation_failed, reason}, socket) do
    socket =
      socket
      |> assign(:generating_content, false)
      |> put_flash(:error, "Failed to generate content: #{reason}")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:email_generated, email_content}, socket) do
    socket =
      socket
      |> assign(:generating_email, false)
      |> assign(:generated_email, email_content)
      |> put_flash(:info, "Follow-up email generated successfully!")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:email_generation_failed, reason}, socket) do
    socket =
      socket
      |> assign(:generating_email, false)
      |> put_flash(:error, "Failed to generate email: #{reason}")

    {:noreply, socket}
  end

  defp get_meeting_for_user!(id, user) do
    from(e in Events.CalendarEvent,
      join: g in assoc(e, :google_account),
      where: e.id == ^id and g.user_id == ^user.id,
      preload: [:google_account, :social_posts]
    )
    |> SMG.Repo.one!()
  end

  defp reload_meeting(socket) do
    meeting = get_meeting_for_user!(socket.assigns.meeting.id, socket.assigns.user)
    assign(socket, :meeting, meeting)
  end

  defp generate_follow_up_email(meeting) do
    if meeting.transcript_url do
      case fetch_transcript_content(meeting.transcript_url) do
        {:ok, transcript} ->
          prompt = build_email_prompt(transcript, meeting)
          call_openai_for_email(prompt)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "No transcript available"}
    end
  end

  defp fetch_transcript_content(url) do
    case Tesla.get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "Failed to fetch transcript: HTTP #{status}"}

      {:error, reason} ->
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp build_email_prompt(transcript, meeting) do
    """
    Based on the following meeting transcript, create a professional follow-up email that summarizes the key points, decisions made, and action items discussed.

    Meeting: #{meeting.title || "Meeting"}
    Date: #{format_date(meeting.start_time)}

    Transcript:
    #{String.slice(transcript, 0, 4000)}

    Please generate a follow-up email with:
    - A clear subject line
    - Brief summary of what was discussed
    - Key decisions or outcomes
    - Action items (if any)
    - Professional and friendly tone

    Format the response as a proper email.
    """
  end

  defp call_openai_for_email(prompt) do
    case OpenAI.chat_completion(
           model: "gpt-4o-mini",
           messages: [
             %{
               role: "system",
               content:
                 "You are a professional assistant helping to write follow-up emails for business meetings."
             },
             %{role: "user", content: prompt}
           ],
           max_tokens: 800,
           temperature: 0.7
         ) do
      {:ok, response} ->
        content =
          response.choices
          |> List.first()
          |> Map.get("message")
          |> Map.get("content")
          |> String.trim()

        {:ok, content}

      {:error, reason} ->
        {:error, "OpenAI API error: #{inspect(reason)}"}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-white" style="background-color: white !important;">
      <!-- Navigation -->
      <.navbar current_user={@user} />
      
    <!-- Main Content -->
      <div
        class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8"
        style="background-color: white !important;"
      >
        <!-- Header -->
        <div class="mb-8">
          <nav class="flex" aria-label="Breadcrumb">
            <ol class="flex items-center space-x-4">
              <li>
                <div>
                  <.link href="/dashboard" class="text-gray-400 hover:text-gray-500">
                    Dashboard
                  </.link>
                </div>
              </li>
              <li>
                <div class="flex items-center">
                  <svg
                    class="flex-shrink-0 h-5 w-5 text-gray-300"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                    aria-hidden="true"
                  >
                    <path
                      fill-rule="evenodd"
                      d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z"
                      clip-rule="evenodd"
                    />
                  </svg>
                  <.link href="/meetings" class="ml-4 text-gray-400 hover:text-gray-500">
                    Meetings
                  </.link>
                </div>
              </li>
              <li>
                <div class="flex items-center">
                  <svg
                    class="flex-shrink-0 h-5 w-5 text-gray-300"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                    aria-hidden="true"
                  >
                    <path
                      fill-rule="evenodd"
                      d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z"
                      clip-rule="evenodd"
                    />
                  </svg>
                  <span class="ml-4 text-sm font-medium text-gray-500">Meeting Details</span>
                </div>
              </li>
            </ol>
          </nav>

          <div class="mt-4 flex items-center justify-between">
            <div class="flex-1 min-w-0">
              <h1 class="text-3xl font-bold text-black">
                {@meeting.title || "Untitled Meeting"}
              </h1>
              <div class="mt-1 flex items-center space-x-2 text-sm text-gray-600">
                <span>{format_datetime(@meeting.start_time)}</span>
                <span>•</span>
                <span>{@meeting.google_account.email}</span>
              </div>
            </div>
            <div class="flex items-center space-x-3">
              <%= if @meeting.transcript_status do %>
                <span class={"inline-flex items-center px-3 py-1 rounded-full text-sm font-medium #{transcript_status_color(@meeting.transcript_status)}"}>
                  {String.capitalize(@meeting.transcript_status)}
                </span>
              <% end %>
            </div>
          </div>
        </div>
        
    <!-- Tabs -->
        <div class="mb-6">
          <div class="border-b border-gray-200">
            <nav class="-mb-px flex space-x-2" aria-label="Tabs">
              <button
                phx-click="switch_tab"
                phx-value-tab="overview"
                class={"#{if @active_tab == "overview", do: "bg-green-100 border-green-500 text-green-700 shadow-sm", else: "bg-white border-gray-200 text-gray-600 hover:text-gray-800 hover:bg-gray-50"} whitespace-nowrap py-3 px-4 border rounded-lg font-medium text-sm transition-all duration-150"}
              >
                Overview
              </button>
              <%= if @meeting.transcript_status == "completed" do %>
                <button
                  phx-click="switch_tab"
                  phx-value-tab="transcript"
                  class={"#{if @active_tab == "transcript", do: "bg-green-100 border-green-500 text-green-700 shadow-sm", else: "bg-white border-gray-200 text-gray-600 hover:text-gray-800 hover:bg-gray-50"} whitespace-nowrap py-3 px-4 border rounded-lg font-medium text-sm transition-all duration-150"}
                >
                  Transcript
                </button>
              <% end %>
              <button
                phx-click="switch_tab"
                phx-value-tab="social"
                class={"#{if @active_tab == "social", do: "bg-green-100 border-green-500 text-green-700 shadow-sm", else: "bg-white border-gray-200 text-gray-600 hover:text-gray-800 hover:bg-gray-50"} whitespace-nowrap py-3 px-4 border rounded-lg font-medium text-sm transition-all duration-150"}
              >
                Social Content ({length(@meeting.social_posts)})
              </button>
              <button
                phx-click="switch_tab"
                phx-value-tab="email"
                class={"#{if @active_tab == "email", do: "bg-green-100 border-green-500 text-green-700 shadow-sm", else: "bg-white border-gray-200 text-gray-600 hover:text-gray-800 hover:bg-gray-50"} whitespace-nowrap py-3 px-4 border rounded-lg font-medium text-sm transition-all duration-150"}
              >
                Follow-up Email
              </button>
            </nav>
          </div>
        </div>
        
    <!-- Tab Content -->
        <%= case @active_tab do %>
          <% "overview" -> %>
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <!-- Meeting Details -->
              <div class="bg-white overflow-hidden shadow rounded-lg">
                <div class="px-4 py-5 sm:p-6">
                  <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Meeting Details</h3>

                  <dl class="space-y-4">
                    <div>
                      <dt class="text-sm font-medium text-gray-500">Start Time</dt>
                      <dd class="mt-1 text-sm text-gray-900">
                        {format_datetime(@meeting.start_time)}
                      </dd>
                    </div>

                    <%= if @meeting.end_time do %>
                      <div>
                        <dt class="text-sm font-medium text-gray-500">End Time</dt>
                        <dd class="mt-1 text-sm text-gray-900">
                          {format_datetime(@meeting.end_time)}
                        </dd>
                      </div>
                    <% end %>

                    <%= if @meeting.description do %>
                      <div>
                        <dt class="text-sm font-medium text-gray-500">Description</dt>
                        <dd class="mt-1 text-sm text-gray-900 whitespace-pre-wrap">
                          {@meeting.description}
                        </dd>
                      </div>
                    <% end %>

                    <%= if @meeting.meeting_link do %>
                      <div>
                        <dt class="text-sm font-medium text-gray-500">Meeting Link</dt>
                        <dd class="mt-1">
                          <a
                            href={@meeting.meeting_link}
                            target="_blank"
                            class="text-green-600 hover:text-green-500 text-sm"
                          >
                            {@meeting.meeting_link}
                          </a>
                        </dd>
                      </div>
                    <% end %>

                    <div>
                      <dt class="text-sm font-medium text-gray-500">AI Notetaker</dt>
                      <dd class="mt-1 text-sm text-gray-900">
                        {if @meeting.notetaker_enabled, do: "Enabled", else: "Disabled"}
                      </dd>
                    </div>

                    <div>
                      <dt class="text-sm font-medium text-gray-500">Bot Status</dt>
                      <dd class="mt-1 text-sm text-gray-900">
                        <%= cond do %>
                          <% @meeting.recall_bot_id && @meeting.transcript_status == "completed" -> %>
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                              🤖 Transcript Ready
                            </span>
                          <% @meeting.recall_bot_id && @meeting.transcript_status == "scheduled" -> %>
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
                              🤖 Bot Deployed
                            </span>
                          <% @meeting.recall_bot_id -> %>
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                              🤖 Bot Active
                            </span>
                          <% true -> %>
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                              No Bot Deployed
                            </span>
                        <% end %>
                      </dd>
                    </div>

                    <div>
                      <dt class="text-sm font-medium text-gray-500">Google Account</dt>
                      <dd class="mt-1 text-sm text-gray-900">{@meeting.google_account.email}</dd>
                    </div>
                  </dl>
                </div>
              </div>
              
    <!-- Quick Actions -->
              <div class="bg-white overflow-hidden shadow rounded-lg">
                <div class="px-4 py-5 sm:p-6">
                  <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Quick Actions</h3>

                  <div class="space-y-3">
                    <%= if @meeting.transcript_status == "completed" do %>
                      <button
                        phx-click="download_transcript"
                        class="w-full inline-flex items-center justify-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                      >
                        📄 Download Transcript
                      </button>

                      <%= if length(@meeting.social_posts) == 0 do %>
                        <button
                          phx-click="generate_social_content"
                          disabled={@generating_content}
                          class={"w-full inline-flex items-center justify-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500 #{if @generating_content, do: "opacity-50 cursor-not-allowed"}"}
                        >
                          <%= if @generating_content do %>
                            <svg
                              class="animate-spin -ml-1 mr-2 h-4 w-4 text-white"
                              fill="none"
                              viewBox="0 0 24 24"
                            >
                              <circle
                                class="opacity-25"
                                cx="12"
                                cy="12"
                                r="10"
                                stroke="currentColor"
                                stroke-width="4"
                              >
                              </circle>
                              <path
                                class="opacity-75"
                                fill="currentColor"
                                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                              >
                              </path>
                            </svg>
                            Generating...
                          <% else %>
                            📱 Generate Social Content
                          <% end %>
                        </button>
                      <% end %>

                      <button
                        phx-click="generate_follow_up_email"
                        disabled={@generating_email}
                        class={"w-full inline-flex items-center justify-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500 #{if @generating_email, do: "opacity-50 cursor-not-allowed"}"}
                      >
                        <%= if @generating_email do %>
                          <svg
                            class="animate-spin -ml-1 mr-2 h-4 w-4 text-gray-700"
                            fill="none"
                            viewBox="0 0 24 24"
                          >
                            <circle
                              class="opacity-25"
                              cx="12"
                              cy="12"
                              r="10"
                              stroke="currentColor"
                              stroke-width="4"
                            >
                            </circle>
                            <path
                              class="opacity-75"
                              fill="currentColor"
                              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                            >
                            </path>
                          </svg>
                          Generating...
                        <% else %>
                          ✉️ Generate Follow-up Email
                        <% end %>
                      </button>
                    <% else %>
                      <!-- Bot deployment controls -->
                      <%= if @meeting.meeting_link do %>
                        <%= if !@meeting.recall_bot_id do %>
                          <button
                            phx-click="deploy_bot"
                            class="w-full inline-flex items-center justify-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                          >
                            🤖 Deploy Bot to Meeting
                          </button>
                        <% else %>
                          <div class="space-y-3">
                            <button
                              phx-click="check_bot_status"
                              class="w-full inline-flex items-center justify-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                            >
                              🔍 Check Bot Status
                            </button>
                          </div>
                        <% end %>
                      <% end %>

                      <div class="text-center py-4">
                        <p class="text-sm text-gray-500">
                          <%= if @meeting.meeting_link do %>
                            Deploy a bot to get meeting transcript and generate content.
                          <% else %>
                            No meeting link available. Cannot deploy bot.
                          <% end %>
                        </p>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          <% "transcript" -> %>
            <%= if @meeting.transcript_status == "completed" && @meeting.transcript_url do %>
              <div class="bg-white shadow rounded-lg">
                <div class="px-4 py-5 sm:p-6">
                  <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Meeting Transcript</h3>
                  <div class="bg-gray-50 rounded-lg p-4 max-h-96 overflow-y-auto">
                    <p class="text-sm text-gray-600 mb-2">
                      <em>
                        Transcript available at:
                        <a
                          href={@meeting.transcript_url}
                          target="_blank"
                          class="text-green-600 hover:text-green-500"
                        >
                          View Full Transcript
                        </a>
                      </em>
                    </p>
                    <p class="text-sm text-gray-900">
                      The full transcript can be accessed via the link above or downloaded using the action button.
                    </p>
                  </div>
                </div>
              </div>
            <% else %>
              <div class="bg-white shadow rounded-lg">
                <div class="px-4 py-5 sm:p-6 text-center">
                  <svg
                    class="mx-auto h-12 w-12 text-gray-400"
                    stroke="currentColor"
                    fill="none"
                    viewBox="0 0 48 48"
                  >
                    <path
                      d="M9 12h6m6 0h6m-6 6h6m-6 6h6M9 18h6m-6 6h6m-6 6h6"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                  </svg>
                  <h3 class="mt-2 text-sm font-medium text-gray-900">No transcript available</h3>
                  <p class="mt-1 text-sm text-gray-500">
                    <%= case @meeting.transcript_status do %>
                      <% "scheduled" -> %>
                        Transcript generation is scheduled.
                      <% "processing" -> %>
                        Transcript is being processed.
                      <% "failed" -> %>
                        Transcript generation failed.
                      <% _ -> %>
                        AI notetaker was not enabled for this meeting.
                    <% end %>
                  </p>
                </div>
              </div>
            <% end %>
          <% "social" -> %>
            <div class="space-y-6">
              <%= if length(@meeting.social_posts) > 0 do %>
                <%= for post <- @meeting.social_posts do %>
                  <div class="bg-white shadow rounded-lg">
                    <div class="px-4 py-5 sm:p-6">
                      <div class="flex items-center justify-between mb-4">
                        <div class="flex items-center space-x-2">
                          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                            {String.capitalize(post.platform)}
                          </span>
                          <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{status_color(post.status)}"}>
                            {String.capitalize(post.status)}
                          </span>
                        </div>
                        <.link
                          href={"/posts/#{post.id}"}
                          class="text-green-600 hover:text-green-500 text-sm font-medium"
                        >
                          Edit & Post
                        </.link>
                      </div>
                      <div class="bg-gray-50 rounded-lg p-4">
                        <p class="text-sm text-gray-900 whitespace-pre-wrap">{post.content}</p>
                      </div>
                    </div>
                  </div>
                <% end %>
              <% else %>
                <div class="bg-white shadow rounded-lg">
                  <div class="px-4 py-5 sm:p-6 text-center">
                    <svg
                      class="mx-auto h-12 w-12 text-gray-400"
                      stroke="currentColor"
                      fill="none"
                      viewBox="0 0 48 48"
                    >
                      <path
                        d="M9 12h6m6 0h6m-6 6h6m-6 6h6M9 18h6m-6 6h6m-6 6h6"
                        stroke-width="2"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                      />
                    </svg>
                    <h3 class="mt-2 text-sm font-medium text-gray-900">
                      No social content generated
                    </h3>
                    <p class="mt-1 text-sm text-gray-500">
                      <%= if @meeting.transcript_status == "completed" do %>
                        Generate social media content from the meeting transcript.
                      <% else %>
                        Social content will be available once the transcript is completed.
                      <% end %>
                    </p>
                    <%= if @meeting.transcript_status == "completed" do %>
                      <div class="mt-6">
                        <button
                          phx-click="generate_social_content"
                          disabled={@generating_content}
                          class={"inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500 #{if @generating_content, do: "opacity-50 cursor-not-allowed"}"}
                        >
                          <%= if @generating_content do %>
                            <svg
                              class="animate-spin -ml-1 mr-2 h-4 w-4 text-white"
                              fill="none"
                              viewBox="0 0 24 24"
                            >
                              <circle
                                class="opacity-25"
                                cx="12"
                                cy="12"
                                r="10"
                                stroke="currentColor"
                                stroke-width="4"
                              >
                              </circle>
                              <path
                                class="opacity-75"
                                fill="currentColor"
                                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                              >
                              </path>
                            </svg>
                            Generating...
                          <% else %>
                            Generate Social Content
                          <% end %>
                        </button>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          <% "email" -> %>
            <div class="bg-white shadow rounded-lg">
              <div class="px-4 py-5 sm:p-6">
                <div class="flex items-center justify-between mb-4">
                  <h3 class="text-lg leading-6 font-medium text-gray-900">Follow-up Email</h3>
                  <%= if @meeting.transcript_status == "completed" do %>
                    <button
                      phx-click="generate_follow_up_email"
                      disabled={@generating_email}
                      class={"inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500 #{if @generating_email, do: "opacity-50 cursor-not-allowed"}"}
                    >
                      <%= if @generating_email do %>
                        <svg
                          class="animate-spin -ml-1 mr-2 h-4 w-4 text-white"
                          fill="none"
                          viewBox="0 0 24 24"
                        >
                          <circle
                            class="opacity-25"
                            cx="12"
                            cy="12"
                            r="10"
                            stroke="currentColor"
                            stroke-width="4"
                          >
                          </circle>
                          <path
                            class="opacity-75"
                            fill="currentColor"
                            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                          >
                          </path>
                        </svg>
                        Generating...
                      <% else %>
                        Generate Email
                      <% end %>
                    </button>
                  <% end %>
                </div>

                <%= if assigns[:generated_email] do %>
                  <div class="bg-gray-50 rounded-lg p-4">
                    <p class="text-sm text-gray-900 whitespace-pre-wrap">{@generated_email}</p>
                  </div>
                <% else %>
                  <div class="text-center py-8">
                    <svg
                      class="mx-auto h-12 w-12 text-gray-400"
                      stroke="currentColor"
                      fill="none"
                      viewBox="0 0 48 48"
                    >
                      <path
                        d="M8 14v20c0 4.418 7.163 8 16 8 1.381 0 2.721-.087 4-.252M8 14c0 4.418 7.163 8 16 8s16-3.582 16-8M8 14c0-4.418 7.163-8 16-8s16 3.582 16 8m0 0v14m-16-5c0 4.418 7.163 8 16 8 1.381 0 2.721-.087 4-.252"
                        stroke-width="2"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                      />
                    </svg>
                    <h3 class="mt-2 text-sm font-medium text-gray-900">
                      No follow-up email generated
                    </h3>
                    <p class="mt-1 text-sm text-gray-500">
                      <%= if @meeting.transcript_status == "completed" do %>
                        Generate a professional follow-up email based on the meeting transcript.
                      <% else %>
                        Email generation will be available once the transcript is completed.
                      <% end %>
                    </p>
                  </div>
                <% end %>
              </div>
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_datetime(nil), do: "No date"

  defp format_datetime(datetime) do
    datetime
    |> Calendar.strftime("%B %d, %Y at %I:%M %p")
  end

  defp format_date(nil), do: "Unknown"

  defp format_date(datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_string()
  end

  defp transcript_status_color("completed"), do: "bg-green-100 text-green-800"
  defp transcript_status_color("scheduled"), do: "bg-yellow-100 text-yellow-800"
  defp transcript_status_color("processing"), do: "bg-blue-100 text-blue-800"
  defp transcript_status_color("failed"), do: "bg-red-100 text-red-800"
  defp transcript_status_color(_), do: "bg-gray-100 text-gray-800"

  defp status_color("draft"), do: "bg-yellow-100 text-yellow-800"
  defp status_color("posted"), do: "bg-green-100 text-green-800"
  defp status_color("failed"), do: "bg-red-100 text-red-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"
end
