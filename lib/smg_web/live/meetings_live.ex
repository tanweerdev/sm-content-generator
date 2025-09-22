defmodule SMGWeb.MeetingsLive do
  use SMGWeb, :live_view
  import Ecto.Query

  alias SMG.{Events}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:user, user)
      |> assign(:filter, "all")
      # Default timezone
      |> assign(:user_timezone, "America/New_York")
      |> load_meetings()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filter = Map.get(params, "filter", "all")

    socket =
      socket
      |> assign(:filter, filter)
      |> load_meetings()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_meetings", %{"filter" => filter}, socket) do
    {:noreply, push_patch(socket, to: "/meetings?filter=#{filter}")}
  end

  @impl true
  def handle_event("timezone_detected", %{"timezone" => timezone}, socket) do
    # Store the user's detected timezone
    {:noreply, assign(socket, :user_timezone, timezone)}
  end

  @impl true
  def handle_event("generate_social_content", %{"event_id" => event_id}, socket) do
    event = Events.get_event!(event_id)

    case SMG.AI.ContentGenerator.generate_social_content(event) do
      {:ok, _social_post} ->
        socket =
          socket
          |> put_flash(:info, "Social media content generated successfully!")
          |> load_meetings()

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, "Failed to generate content: #{reason}")

        {:noreply, socket}
    end
  end

  defp load_meetings(socket) do
    user = socket.assigns.user
    filter = socket.assigns.filter

    meetings = get_all_meetings(user, filter)
    {upcoming_meetings, past_meetings} = separate_meetings_by_time(meetings)

    socket
    |> assign(:meetings, meetings)
    |> assign(:upcoming_meetings, upcoming_meetings)
    |> assign(:past_meetings, past_meetings)
  end

  defp get_all_meetings(user, filter) do
    base_query =
      from(e in Events.CalendarEvent,
        join: g in assoc(e, :google_account),
        where: g.user_id == ^user.id and not is_nil(e.start_time),
        order_by: [desc: e.start_time],
        preload: [:google_account, :social_posts]
      )

    filtered_query =
      case filter do
        "with_transcript" ->
          from(e in base_query, where: e.transcript_status == "completed")

        "with_social_posts" ->
          from(e in base_query,
            join: sp in assoc(e, :social_posts),
            distinct: true
          )

        "scheduled_notetaker" ->
          from(e in base_query, where: e.notetaker_enabled == true)

        # "all"
        _ ->
          base_query
      end

    SMG.Repo.all(filtered_query)
  end

  defp separate_meetings_by_time(meetings) do
    now = DateTime.utc_now()

    {upcoming, past} =
      Enum.split_with(meetings, fn meeting ->
        DateTime.compare(meeting.start_time, now) == :gt
      end)

    # Sort upcoming meetings by start time (earliest first)
    upcoming = Enum.sort_by(upcoming, & &1.start_time, DateTime)

    {upcoming, past}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="min-h-screen bg-white"
      style="background-color: white !important;"
      phx-hook="TimezoneDetector"
      id="meetings-timezone-detector"
    >
      <!-- Navigation -->
      <.navbar current_user={@user} />
      
    <!-- Main Content -->
      <div
        class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8"
        style="background-color: white !important;"
      >
        <!-- Header -->
        <div class="mb-8">
          <div>
            <h1 class="text-3xl font-bold text-black">Meetings</h1>
            <p class="mt-1 text-sm text-gray-600">
              View upcoming and past meetings, transcripts, and generated content
            </p>
          </div>
        </div>
        
    <!-- Filter Tabs -->
        <div class="mb-6">
          <div class="border-b border-gray-200">
            <nav class="-mb-px flex space-x-2" aria-label="Tabs">
              <button
                phx-click="filter_meetings"
                phx-value-filter="all"
                class={"#{if @filter == "all", do: "bg-green-100 border-green-500 text-green-700 shadow-sm", else: "bg-white border-gray-200 text-gray-600 hover:text-gray-800 hover:bg-gray-50"} whitespace-nowrap py-3 px-4 border rounded-lg font-medium text-sm transition-all duration-150"}
              >
                All Meetings
              </button>
              <button
                phx-click="filter_meetings"
                phx-value-filter="with_transcript"
                class={"#{if @filter == "with_transcript", do: "bg-green-100 border-green-500 text-green-700 shadow-sm", else: "bg-white border-gray-200 text-gray-600 hover:text-gray-800 hover:bg-gray-50"} whitespace-nowrap py-3 px-4 border rounded-lg font-medium text-sm transition-all duration-150"}
              >
                With Transcripts
              </button>
              <button
                phx-click="filter_meetings"
                phx-value-filter="with_social_posts"
                class={"#{if @filter == "with_social_posts", do: "bg-green-100 border-green-500 text-green-700 shadow-sm", else: "bg-white border-gray-200 text-gray-600 hover:text-gray-800 hover:bg-gray-50"} whitespace-nowrap py-3 px-4 border rounded-lg font-medium text-sm transition-all duration-150"}
              >
                With Social Content
              </button>
              <button
                phx-click="filter_meetings"
                phx-value-filter="scheduled_notetaker"
                class={"#{if @filter == "scheduled_notetaker", do: "bg-green-100 border-green-500 text-green-700 shadow-sm", else: "bg-white border-gray-200 text-gray-600 hover:text-gray-800 hover:bg-gray-50"} whitespace-nowrap py-3 px-4 border rounded-lg font-medium text-sm transition-all duration-150"}
              >
                AI Notetaker Enabled
              </button>
            </nav>
          </div>
        </div>
        
    <!-- Meetings List -->
        <%= if @meetings == [] do %>
          <div class="text-center py-12">
            <svg
              class="mx-auto h-12 w-12 text-gray-400"
              stroke="currentColor"
              fill="none"
              viewBox="0 0 48 48"
            >
              <path
                d="M34 40h10v-4a6 6 0 00-10.712-3.714M34 40H14m20 0v-4a9.971 9.971 0 00-.712-3.714M14 40H4v-4a6 6 0 0110.713-3.714M14 40v-4c0-1.313.253-2.566.713-3.714m0 0A9.971 9.971 0 0124 24c4.21 0 7.813 2.602 9.288 6.286"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
            <h3 class="mt-2 text-sm font-medium text-gray-900">No meetings found</h3>
            <p class="mt-1 text-sm text-gray-500">
              <%= case @filter do %>
                <% "with_transcript" -> %>
                  No meetings with transcripts yet.
                <% "with_social_posts" -> %>
                  No meetings with social content generated yet.
                <% "scheduled_notetaker" -> %>
                  No meetings with AI notetaker enabled yet.
                <% _ -> %>
                  No meetings found.
              <% end %>
            </p>
          </div>
        <% else %>
          <!-- Upcoming Meetings -->
          <%= if @upcoming_meetings != [] do %>
            <div class="mb-8">
              <h2 class="text-xl font-semibold text-gray-900 mb-4">Upcoming Meetings</h2>
              <div class="bg-white shadow overflow-hidden sm:rounded-md">
                <ul class="divide-y divide-gray-200">
                  <%= for meeting <- @upcoming_meetings do %>
                    <li class="hover:bg-gray-50">
                      <div class="px-4 py-4 sm:px-6">
                        <div class="flex items-center justify-between">
                          <div class="flex-1 min-w-0">
                            <div class="flex items-center space-x-3">
                              <div class="flex-shrink-0">
                                <%= cond do %>
                                  <% meeting.meeting_link && String.contains?(meeting.meeting_link, "zoom") -> %>
                                    <div class="h-8 w-8 rounded-lg">
                                      <img src={~p"/images/zoom.png"} width="36" />
                                    </div>
                                  <% meeting.meeting_link && String.contains?(meeting.meeting_link, "meet.google") -> %>
                                    <div class="h-8 w-8 rounded-lg">
                                      <img src={~p"/images/google_meet.png"} width="36" />
                                    </div>
                                  <% meeting.meeting_link && String.contains?(meeting.meeting_link, "teams") -> %>
                                    <div class="h-8 w-8 rounded-lg bg-purple-500 flex items-center justify-center shadow-sm border-2 border-purple-600">
                                      <svg
                                        class="h-5 w-5 text-white"
                                        viewBox="0 0 24 24"
                                        fill="currentColor"
                                      >
                                        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.94-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z" />
                                      </svg>
                                    </div>
                                  <% meeting.meeting_link -> %>
                                    <div class="h-8 w-8 rounded-lg bg-gray-400 flex items-center justify-center shadow-sm border-2 border-gray-500">
                                      <svg
                                        class="h-5 w-5 text-white"
                                        fill="none"
                                        stroke="currentColor"
                                        viewBox="0 0 24 24"
                                      >
                                        <path
                                          stroke-linecap="round"
                                          stroke-linejoin="round"
                                          stroke-width="2"
                                          d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"
                                        />
                                      </svg>
                                    </div>
                                  <% true -> %>
                                    <span></span>
                                <% end %>
                              </div>
                              <div class="flex-1 min-w-0">
                                <p class="text-sm font-medium text-gray-900 truncate">
                                  {meeting.title || "Untitled Meeting"}
                                </p>
                                <div class="flex items-center space-x-2 mt-1">
                                  <p class="text-sm text-blue-600 font-medium">
                                    {format_datetime(meeting.start_time, @user_timezone)}
                                  </p>
                                  <span class="text-gray-300">•</span>
                                  <p class="text-sm text-gray-500">
                                    {meeting.google_account.email}
                                  </p>
                                </div>
                              </div>
                            </div>
                          </div>
                          <div class="flex flex-col space-y-2">
                            <.link
                              href={"/meetings/#{meeting.id}"}
                              class="inline-flex items-center px-3 py-1 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                            >
                              View Details
                            </.link>
                          </div>
                        </div>
                      </div>
                    </li>
                  <% end %>
                </ul>
              </div>
            </div>
          <% end %>
          
    <!-- Past Meetings -->
          <%= if @past_meetings != [] do %>
            <div>
              <h2 class="text-xl font-semibold text-gray-900 mb-4">Past Meetings</h2>
              <div class="bg-white shadow overflow-hidden sm:rounded-md">
                <ul class="divide-y divide-gray-200">
                  <%= for meeting <- @past_meetings do %>
                    <li class="hover:bg-gray-50">
                      <div class="px-4 py-4 sm:px-6">
                        <div class="flex items-center justify-between">
                          <div class="flex-1 min-w-0">
                            <div class="flex items-center space-x-3">
                              <div class="flex-shrink-0">
                                <%= cond do %>
                                  <% meeting.meeting_link && String.contains?(meeting.meeting_link, "zoom") -> %>
                                    <div class="h-8 w-8 rounded-lg">
                                      <img src={~p"/images/zoom.png"} width="36" />
                                    </div>
                                  <% meeting.meeting_link && String.contains?(meeting.meeting_link, "meet.google") -> %>
                                    <div class="h-8 w-8 rounded-lg">
                                      <img src={~p"/images/google_meet.png"} width="36" />
                                    </div>
                                  <% meeting.meeting_link && String.contains?(meeting.meeting_link, "teams") -> %>
                                    <div class="h-8 w-8 rounded-lg bg-purple-500 flex items-center justify-center shadow-sm border-2 border-purple-600">
                                      <svg
                                        class="h-5 w-5 text-white"
                                        viewBox="0 0 24 24"
                                        fill="currentColor"
                                      >
                                        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.94-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z" />
                                      </svg>
                                    </div>
                                  <% meeting.meeting_link -> %>
                                    <div class="h-8 w-8 rounded-lg bg-gray-400 flex items-center justify-center shadow-sm border-2 border-gray-500">
                                      <svg
                                        class="h-5 w-5 text-white"
                                        fill="none"
                                        stroke="currentColor"
                                        viewBox="0 0 24 24"
                                      >
                                        <path
                                          stroke-linecap="round"
                                          stroke-linejoin="round"
                                          stroke-width="2"
                                          d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"
                                        />
                                      </svg>
                                    </div>
                                  <% true -> %>
                                    <span></span>
                                <% end %>
                              </div>

                              <div class="flex-1 min-w-0">
                                <p class="text-sm font-medium text-gray-900 truncate">
                                  {meeting.title || "Untitled Meeting"}
                                </p>
                                <div class="flex items-center space-x-2 mt-1">
                                  <p class="text-sm text-gray-500">
                                    {format_datetime(meeting.start_time, @user_timezone)}
                                  </p>
                                  <span class="text-gray-300">•</span>
                                  <p class="text-sm text-gray-500">
                                    {meeting.google_account.email}
                                  </p>
                                </div>
                              </div>
                            </div>
                            
    <!-- Meeting Description -->
                            <%= if meeting.description && String.length(meeting.description) > 0 do %>
                              <div class="mt-2">
                                <p class="text-sm text-gray-600 line-clamp-2">
                                  {String.slice(meeting.description, 0, 150)}{if String.length(
                                                                                   meeting.description
                                                                                 ) > 150,
                                                                                 do: "..."}
                                </p>
                              </div>
                            <% end %>
                            
    <!-- Status Badges -->
                            <div class="space-y-3 mt-3">
                              <div class="flex items-center space-x-2">
                                <%= if meeting.notetaker_enabled do %>
                                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                                    🤖 AI Notetaker
                                  </span>
                                <% end %>

                                <%= if meeting.transcript_status do %>
                                  <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{transcript_status_color(meeting.transcript_status)}"}>
                                    {String.capitalize(meeting.transcript_status)}
                                  </span>
                                <% end %>

                                <%= if meeting.attendee_count > 0 do %>
                                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800">
                                    👥 {meeting.attendee_count} attendee{if meeting.attendee_count !=
                                                                             1,
                                                                           do: "s"}
                                  </span>
                                <% end %>

                                <%= if length(meeting.social_posts) > 0 do %>
                                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                                    📱 {length(meeting.social_posts)} Social Post(s)
                                  </span>
                                <% end %>
                              </div>

                              <%= if meeting.attendee_count > 0 do %>
                                <div class="w-full">
                                  <div class="flex flex-wrap gap-1 mt-2 break-all">
                                    <%= for email <- meeting.attendee_emails do %>
                                      <span class="inline-block px-2 py-1 rounded-md text-xs bg-blue-50 text-blue-700 border border-blue-200 max-w-full break-all">
                                        {email}
                                      </span>
                                    <% end %>
                                  </div>
                                </div>
                              <% end %>
                            </div>
                          </div>
                          
    <!-- Actions -->
                          <div class="flex flex-col space-y-2">
                            <.link
                              href={"/meetings/#{meeting.id}"}
                              class="inline-flex items-center px-3 py-1 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                            >
                              View Details
                            </.link>

                            <%= if meeting.transcript_status == "completed" && length(meeting.social_posts) == 0 do %>
                              <button
                                phx-click="generate_social_content"
                                phx-value-event_id={meeting.id}
                                class="inline-flex items-center px-3 py-1 border border-transparent text-sm leading-4 font-medium rounded-md text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                              >
                                Generate Content
                              </button>
                            <% end %>
                          </div>
                        </div>
                      </div>
                    </li>
                  <% end %>
                </ul>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_datetime(nil), do: "No date"

  defp format_datetime(datetime, timezone \\ "America/New_York") do
    # Try to convert to user's timezone, fallback to UTC if timezone conversion fails
    try do
      local_datetime = DateTime.shift_zone!(datetime, timezone)

      local_datetime
      |> Calendar.strftime("%B %d, %Y at %I:%M %p %Z")
    rescue
      _ ->
        # Fallback to UTC if timezone conversion fails
        datetime
        |> Calendar.strftime("%B %d, %Y at %I:%M %p UTC")
    end
  end

  defp transcript_status_color("completed"), do: "bg-green-100 text-green-800"
  defp transcript_status_color("scheduled"), do: "bg-yellow-100 text-yellow-800"
  defp transcript_status_color("processing"), do: "bg-blue-100 text-blue-800"
  defp transcript_status_color("failed"), do: "bg-red-100 text-red-800"
  defp transcript_status_color(_), do: "bg-gray-100 text-gray-800"
end
