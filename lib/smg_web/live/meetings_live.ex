defmodule SMGWeb.MeetingsLive do
  use SMGWeb, :live_view
  import Ecto.Query

  alias SMG.{Events, Social}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:user, user)
      |> assign(:filter, "all")
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
            <nav class="-mb-px flex space-x-8" aria-label="Tabs">
              <button
                phx-click="filter_meetings"
                phx-value-filter="all"
                class={"#{if @filter == "all", do: "border-green-500 text-green-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"} whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm"}
              >
                All Meetings
              </button>
              <button
                phx-click="filter_meetings"
                phx-value-filter="with_transcript"
                class={"#{if @filter == "with_transcript", do: "border-green-500 text-green-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"} whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm"}
              >
                With Transcripts
              </button>
              <button
                phx-click="filter_meetings"
                phx-value-filter="with_social_posts"
                class={"#{if @filter == "with_social_posts", do: "border-green-500 text-green-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"} whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm"}
              >
                With Social Content
              </button>
              <button
                phx-click="filter_meetings"
                phx-value-filter="scheduled_notetaker"
                class={"#{if @filter == "scheduled_notetaker", do: "border-green-500 text-green-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"} whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm"}
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
                                <div class="h-10 w-10 rounded-full bg-blue-100 flex items-center justify-center">
                                  <svg
                                    class="h-5 w-5 text-blue-600"
                                    fill="currentColor"
                                    viewBox="0 0 20 20"
                                  >
                                    <path
                                      fill-rule="evenodd"
                                      d="M6 2a1 1 0 00-1 1v1H4a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V6a2 2 0 00-2-2h-1V3a1 1 0 10-2 0v1H7V3a1 1 0 00-1-1zm0 5a1 1 0 000 2h8a1 1 0 100-2H6z"
                                      clip-rule="evenodd"
                                    />
                                  </svg>
                                </div>
                              </div>
                              <div class="flex-1 min-w-0">
                                <p class="text-sm font-medium text-gray-900 truncate">
                                  {meeting.title || "Untitled Meeting"}
                                </p>
                                <div class="flex items-center space-x-2 mt-1">
                                  <p class="text-sm text-blue-600 font-medium">
                                    {format_datetime(meeting.start_time)}
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
                                    <div class="h-10 w-10 rounded-full bg-blue-100 flex items-center justify-center">
                                      <span class="text-blue-600 font-medium text-sm">Zoom</span>
                                    </div>
                                  <% meeting.meeting_link && String.contains?(meeting.meeting_link, "meet.google") -> %>
                                    <div class="h-10 w-10 rounded-full bg-green-100 flex items-center justify-center">
                                      <span class="text-green-600 font-medium text-sm">Meet</span>
                                    </div>
                                  <% meeting.meeting_link && String.contains?(meeting.meeting_link, "teams") -> %>
                                    <div class="h-10 w-10 rounded-full bg-purple-100 flex items-center justify-center">
                                      <span class="text-purple-600 font-medium text-sm">Teams</span>
                                    </div>
                                  <% true -> %>
                                    <div class="h-10 w-10 rounded-full bg-gray-100 flex items-center justify-center">
                                      <svg
                                        class="h-5 w-5 text-gray-600"
                                        fill="currentColor"
                                        viewBox="0 0 20 20"
                                      >
                                        <path d="M2.003 5.884L10 9.882l7.997-3.998A2 2 0 0016 4H4a2 2 0 00-1.997 1.884z" />
                                        <path d="M18 8.118l-8 4-8-4V14a2 2 0 002 2h12a2 2 0 002-2V8.118z" />
                                      </svg>
                                    </div>
                                <% end %>
                              </div>

                              <div class="flex-1 min-w-0">
                                <p class="text-sm font-medium text-gray-900 truncate">
                                  {meeting.title || "Untitled Meeting"}
                                </p>
                                <div class="flex items-center space-x-2 mt-1">
                                  <p class="text-sm text-gray-500">
                                    {format_datetime(meeting.start_time)}
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

  defp format_datetime(datetime) do
    datetime
    |> Calendar.strftime("%B %d, %Y at %I:%M %p")
  end

  defp transcript_status_color("completed"), do: "bg-green-100 text-green-800"
  defp transcript_status_color("scheduled"), do: "bg-yellow-100 text-yellow-800"
  defp transcript_status_color("processing"), do: "bg-blue-100 text-blue-800"
  defp transcript_status_color("failed"), do: "bg-red-100 text-red-800"
  defp transcript_status_color(_), do: "bg-gray-100 text-gray-800"

  defp format_attendee_tooltip(attendee_emails) when is_list(attendee_emails) do
    case attendee_emails do
      [] ->
        "No attendee emails available"

      emails when length(emails) <= 5 ->
        "Attendees: " <> Enum.join(emails, ", ")

      emails ->
        first_five = Enum.take(emails, 5)
        remaining = length(emails) - 5
        "Attendees: " <> Enum.join(first_five, ", ") <> " and #{remaining} more"
    end
  end

  defp format_attendee_tooltip(_), do: "No attendee emails available"
end
