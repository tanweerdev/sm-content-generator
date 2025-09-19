defmodule SMGWeb.DashboardLive do
  use SMGWeb, :live_view

  alias SMG.{Accounts, Events, Social}
  alias SMG.Integrations.GoogleCalendar

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if user do
      socket =
        socket
        |> assign(:user, user)
        |> assign(:loading, false)
        |> load_data()

      {:ok, socket}
    else
      {:ok, redirect(socket, to: "/")}
    end
  end

  @impl true
  def handle_event("sync_calendar", %{"account_id" => account_id}, socket) do
    account = Accounts.get_google_account(account_id)

    socket =
      case GoogleCalendar.sync_events(account) do
        {:ok, _results} ->
          socket
          |> put_flash(:info, "Calendar synced successfully!")
          |> load_data()

        {:error, reason} ->
          put_flash(socket, :error, "Failed to sync calendar: #{reason}")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_notetaker", %{"event_id" => event_id}, socket) do
    event = Events.get_event!(event_id)

    socket =
      case Events.toggle_notetaker(event) do
        {:ok, updated_event} ->
          # If notetaker was enabled and there's a meeting link, schedule the bot
          if updated_event.notetaker_enabled && updated_event.meeting_link do
            case SMG.Integrations.RecallAI.schedule_bot_for_event(updated_event) do
              {:ok, _} ->
                socket
                |> put_flash(:info, "Notetaker scheduled for meeting!")
                |> load_data()

              {:error, reason} ->
                put_flash(socket, :error, "Failed to schedule notetaker: #{reason}")
            end
          else
            socket
            |> put_flash(:info, "Notetaker setting updated!")
            |> load_data()
          end

        {:error, _changeset} ->
          put_flash(socket, :error, "Failed to update notetaker setting")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("add_google_account", _params, socket) do
    {:noreply, redirect(socket, to: "/auth/google")}
  end

  defp load_data(socket) do
    user = socket.assigns.user

    google_accounts = Accounts.list_user_google_accounts(user)
    upcoming_events = Events.list_upcoming_events_for_user(user, 20)
    draft_posts = Social.list_draft_posts_for_user(user)

    socket
    |> assign(:google_accounts, google_accounts)
    |> assign(:upcoming_events, upcoming_events)
    |> assign(:draft_posts, draft_posts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <!-- Header -->
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900">
            Welcome back, <%= @user.name || @user.email %>
          </h1>
          <p class="mt-1 text-sm text-gray-600">
            Manage your meetings and generate social content
          </p>
        </div>

        <!-- Google Accounts Section -->
        <div class="bg-white overflow-hidden shadow rounded-lg mb-8">
          <div class="px-4 py-5 sm:p-6">
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-lg leading-6 font-medium text-gray-900">
                Connected Google Accounts
              </h3>
              <button
                phx-click="add_google_account"
                class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              >
                Connect Google Account
              </button>
            </div>

            <%= if @google_accounts == [] do %>
              <div class="text-center py-6">
                <svg class="mx-auto h-12 w-12 text-gray-400" stroke="currentColor" fill="none" viewBox="0 0 48 48">
                  <path d="M34 40h10v-4a6 6 0 00-10.712-3.714M34 40H14m20 0v-4a9.971 9.971 0 00-.712-3.714M14 40H4v-4a6 6 0 0110.713-3.714M14 40v-4c0-1.313.253-2.566.713-3.714m0 0A9.971 9.971 0 0124 24c4.21 0 7.813 2.602 9.288 6.286" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                </svg>
                <h3 class="mt-2 text-sm font-medium text-gray-900">No Google accounts connected</h3>
                <p class="mt-1 text-sm text-gray-500">
                  Connect your Google account to sync calendar events.
                </p>
              </div>
            <% else %>
              <div class="space-y-3">
                <%= for account <- @google_accounts do %>
                  <div class="flex items-center justify-between p-3 border border-gray-200 rounded-lg">
                    <div class="flex items-center space-x-3">
                      <div class="flex-shrink-0">
                        <svg class="h-6 w-6 text-blue-500" fill="currentColor" viewBox="0 0 20 20">
                          <path d="M2.003 5.884L10 9.882l7.997-3.998A2 2 0 0016 4H4a2 2 0 00-1.997 1.884z" />
                          <path d="M18 8.118l-8 4-8-4V14a2 2 0 002 2h12a2 2 0 002-2V8.118z" />
                        </svg>
                      </div>
                      <div>
                        <p class="text-sm font-medium text-gray-900"><%= account.email %></p>
                        <p class="text-sm text-gray-500">Google Calendar</p>
                      </div>
                    </div>
                    <button
                      phx-click="sync_calendar"
                      phx-value-account_id={account.id}
                      class="inline-flex items-center px-3 py-1 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                    >
                      Sync Calendar
                    </button>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Main Content Grid -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
          <!-- Upcoming Events -->
          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
              <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">
                Upcoming Events
              </h3>

              <%= if @upcoming_events == [] do %>
                <div class="text-center py-6">
                  <svg class="mx-auto h-12 w-12 text-gray-400" stroke="currentColor" fill="none" viewBox="0 0 48 48">
                    <path d="M8 14v20c0 4.418 7.163 8 16 8 1.381 0 2.721-.087 4-.252M8 14c0 4.418 7.163 8 16 8s16-3.582 16-8M8 14c0-4.418 7.163-8 16-8s16 3.582 16 8m0 0v14m-16-5c0 4.418 7.163 8 16 8 1.381 0 2.721-.087 4-.252" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                  </svg>
                  <h3 class="mt-2 text-sm font-medium text-gray-900">No upcoming events</h3>
                  <p class="mt-1 text-sm text-gray-500">
                    Connect your Google Calendar to see upcoming events.
                  </p>
                </div>
              <% else %>
                <div class="space-y-3">
                  <%= for event <- @upcoming_events do %>
                    <div class="border border-gray-200 rounded-lg p-4">
                      <div class="flex items-start justify-between">
                        <div class="flex-1">
                          <h4 class="text-sm font-medium text-gray-900">
                            <%= event.title || "Untitled Event" %>
                          </h4>
                          <p class="text-sm text-gray-500 mt-1">
                            <%= format_datetime(event.start_time) %>
                          </p>
                          <%= if event.meeting_link do %>
                            <p class="text-xs text-green-600 mt-1">
                              📞 Meeting link available
                            </p>
                          <% end %>
                        </div>
                        <div class="ml-4">
                          <label class="inline-flex items-center">
                            <input
                              type="checkbox"
                              checked={event.notetaker_enabled}
                              phx-click="toggle_notetaker"
                              phx-value-event_id={event.id}
                              class="form-checkbox h-4 w-4 text-indigo-600 transition duration-150 ease-in-out"
                            />
                            <span class="ml-2 text-sm text-gray-700">AI Notetaker</span>
                          </label>
                        </div>
                      </div>
                      <%= if event.transcript_status do %>
                        <div class="mt-2">
                          <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{transcript_status_color(event.transcript_status)}"}>
                            <%= String.capitalize(event.transcript_status) %>
                          </span>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Draft Posts -->
          <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
              <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">
                Generated Content
              </h3>

              <%= if @draft_posts == [] do %>
                <div class="text-center py-6">
                  <svg class="mx-auto h-12 w-12 text-gray-400" stroke="currentColor" fill="none" viewBox="0 0 48 48">
                    <path d="M9 12h6m6 0h6m-6 6h6m-6 6h6M9 18h6m-6 6h6m-6 6h6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                  </svg>
                  <h3 class="mt-2 text-sm font-medium text-gray-900">No content generated yet</h3>
                  <p class="mt-1 text-sm text-gray-500">
                    Content will appear here after meetings with AI notetaker enabled.
                  </p>
                </div>
              <% else %>
                <div class="space-y-4">
                  <%= for post <- @draft_posts do %>
                    <div class="border border-gray-200 rounded-lg p-4">
                      <div class="flex items-start justify-between mb-2">
                        <div class="flex items-center space-x-2">
                          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                            <%= String.capitalize(post.platform) %>
                          </span>
                          <span class="text-xs text-gray-500">
                            <%= if post.calendar_event do %>
                              From: <%= post.calendar_event.title || "Meeting" %>
                            <% end %>
                          </span>
                        </div>
                        <.link href={"/posts/#{post.id}"} class="text-indigo-600 hover:text-indigo-500 text-sm font-medium">
                          Edit & Post
                        </.link>
                      </div>
                      <p class="text-sm text-gray-900 line-clamp-3">
                        <%= post.content %>
                      </p>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
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
  defp transcript_status_color("failed"), do: "bg-red-100 text-red-800"
  defp transcript_status_color(_), do: "bg-gray-100 text-gray-800"
end