defmodule SMGWeb.DashboardLive do
  use SMGWeb, :live_view

  alias SMG.{Accounts, Events, Social}
  alias SMG.Integrations.GoogleCalendar

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:user, user)
      |> assign(:loading, false)
      |> assign(:reprocessing_event_id, nil)
      # Default timezone
      |> assign(:user_timezone, "America/New_York")
      |> load_data()

    case Accounts.list_user_google_accounts(user) do
      google_accounts = [google_account | _] ->
        Enum.each(google_accounts, fn account ->
          if account do
            send(self(), {:auto_sync_calendar, google_account.id})
          end
        end)

      [] ->
        :ok
    end

    {:ok, socket}
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

  @impl true
  def handle_event("reprocess_automation", %{"event_id" => event_id}, socket) do
    event = Events.get_event!(event_id)

    socket = assign(socket, :reprocessing_event_id, String.to_integer(event_id))

    # Process in the background
    parent_pid = self()

    Task.start(fn ->
      case SMG.AI.ContentGenerator.generate_social_content(event) do
        {:ok, results} ->
          post_count = length(results)
          send(parent_pid, {:reprocess_completed, event.id, :success, post_count})

        {:error, reason} ->
          send(parent_pid, {:reprocess_completed, event.id, :error, reason})
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("timezone_detected", %{"timezone" => timezone}, socket) do
    # Store the user's detected timezone
    {:noreply, assign(socket, :user_timezone, timezone)}
  end

  @impl true
  def handle_event("sync_latest_events", _params, socket) do
    user = socket.assigns.user

    case Accounts.list_user_google_accounts(user) do
      google_accounts = [_google_account | _] ->
        socket =
          socket
          |> assign(:loading, true)

        parent_pid = self()

        Enum.each(google_accounts, fn account ->
          if account do
            Task.start(fn ->
              try do
                case GoogleCalendar.sync_events(account) do
                  {:ok, _results} ->
                    send(parent_pid, {:sync_completed, :success, account.email})

                  {:error, reason} ->
                    send(parent_pid, {:sync_completed, {:error, reason}})
                end
              rescue
                error ->
                  # If sync fails with an exception, still reset the loading state
                  send(parent_pid, {:sync_completed, {:error, "Sync failed: #{inspect(error)}"}})
              end
            end)
          end
        end)

        # Add a timeout to reset loading state in case messages don't arrive
        # 30 second timeout
        Process.send_after(self(), {:sync_timeout}, 30_000)

        {:noreply, socket}

      [] ->
        socket =
          socket
          |> put_flash(
            :error,
            "No Google account connected. Please connect your Google account first."
          )

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:auto_sync_calendar, account_id}, socket) do
    account = Accounts.get_google_account(account_id)

    socket =
      socket
      |> assign(:loading, true)

    parent_pid = self()

    Task.start(fn ->
      try do
        case GoogleCalendar.sync_events(account) do
          {:ok, _results} ->
            send(parent_pid, {:sync_completed, :success, account.email})

          {:error, reason} ->
            send(parent_pid, {:sync_completed, {:error, reason}})
        end
      rescue
        error ->
          # If sync fails with an exception, still reset the loading state
          send(parent_pid, {:sync_completed, {:error, "Auto-sync failed: #{inspect(error)}"}})
      end
    end)

    # Add a timeout to reset loading state in case messages don't arrive
    # 30 second timeout
    Process.send_after(self(), {:sync_timeout}, 30_000)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:sync_completed, :success, email}, socket) do
    socket =
      socket
      |> assign(:loading, false)
      |> put_flash(:info, "Calendar synced successfully for #{email}!")
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:sync_completed, {:error, reason}}, socket) do
    socket =
      socket
      |> assign(:loading, false)
      |> put_flash(:error, "Failed to sync calendar: #{reason}")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:reprocess_completed, _event_id, :success, post_count}, socket) do
    socket =
      socket
      |> assign(:reprocessing_event_id, nil)
      |> put_flash(
        :info,
        "✨ Successfully generated #{post_count} social media post(s) for this meeting!"
      )
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:reprocess_completed, _event_id, :error, reason}, socket) do
    socket =
      socket
      |> assign(:reprocessing_event_id, nil)
      |> put_flash(:error, "Failed to reprocess automation: #{reason}")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:sync_timeout}, socket) do
    # Only reset loading if it's still true (sync hasn't completed yet)
    if socket.assigns.loading == true do
      socket =
        socket
        |> assign(:loading, false)
        |> put_flash(:error, "Sync operation timed out. Please try again.")

      {:noreply, socket}
    else
      # Sync already completed, ignore timeout
      {:noreply, socket}
    end
  end

  defp load_data(socket) do
    user = socket.assigns.user

    google_accounts = Accounts.list_user_google_accounts(user)
    upcoming_events = Events.list_upcoming_events_for_user(user, 5)
    past_events = Events.list_past_events_for_user(user, 5)
    all_events = Events.list_events_for_user(user)
    draft_posts = Social.list_draft_posts_for_user(user)

    socket
    |> assign(:google_accounts, google_accounts)
    |> assign(:upcoming_events, upcoming_events)
    |> assign(:past_events, past_events)
    |> assign(:all_events, all_events)
    |> assign(:draft_posts, draft_posts)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="min-h-screen bg-white"
      style="background-color: white !important;"
      phx-hook="TimezoneDetector"
      id="timezone-detector"
    >
      <!-- Flash Messages -->
      <SMGWeb.Layouts.flash_group flash={@flash} />
      
    <!-- Navigation -->
      <.navbar current_user={@user} />

      <!-- Dashboard Actions -->
      <div class="bg-gray-50 border-b border-gray-200">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center py-3">
            <h1 class="text-2xl font-bold text-gray-900">Dashboard</h1>
            <button
              phx-click="sync_latest_events"
              disabled={@loading == true}
              title={
                if @loading == true,
                  do: "Syncing calendar events...",
                  else: "Sync latest events from Google Calendar"
              }
              class={[
                "inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500",
                if(@loading == true, do: "opacity-50 cursor-not-allowed")
              ]}
            >
              <%= if @loading == true do %>
                <svg class="w-4 h-4 animate-spin mr-2" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                Syncing...
              <% else %>
                <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                </svg>
                Sync Calendar
              <% end %>
            </button>
          </div>
        </div>
      </div>

    <!-- Main Content -->
      <div
        class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8"
        style="background-color: white !important;"
      >
        
    <!-- Main Content Grid -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
          <!-- Upcoming Events -->
          <div class="bg-white border border-gray-100 rounded-xl overflow-hidden">
            <div class="px-6 py-5">
              <div class="flex items-center justify-between mb-6">
                <h3 class="text-lg font-semibold text-black">
                  Upcoming Events
                </h3>
                <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800">
                  {length(@upcoming_events)} events
                </span>
              </div>

              <%= if @upcoming_events == [] do %>
                <div class="text-center py-8">
                  <div class="w-12 h-12 bg-gray-100 rounded-full flex items-center justify-center mx-auto mb-4">
                    <svg
                      class="w-6 h-6 text-gray-400"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M8 7V3a1 1 0 011-1h6a1 1 0 011 1v4h4V3a1 1 0 011-1h6a1 1 0 011 1v4h2a2 2 0 012 2v1H6V9a2 2 0 012-2h0zM6 12v24a2 2 0 002 2h32a2 2 0 002-2V12H6z"
                      />
                    </svg>
                  </div>
                  <h3 class="text-sm font-medium text-black mb-1">No upcoming events</h3>
                  <p class="text-sm text-gray-500">
                    Connect your Google Calendar to see upcoming events.
                  </p>
                </div>
              <% else %>
                <div class="space-y-4">
                  <%= for event <- @upcoming_events do %>
                    <div class="border border-gray-100 rounded-lg p-4 hover:border-green-200 hover:bg-green-50 transition-all duration-200">
                      <div class="flex items-start justify-between">
                        <div class="flex-1">
                          <div class="flex items-start justify-between mb-3">
                            <div>
                              <div class="flex items-center space-x-3 mb-1">
                                <h4 class="text-sm font-semibold text-black">
                                  {event.title || "Untitled Event"}
                                </h4>
                                <%= cond do %>
                                  <% event.meeting_link && String.contains?(event.meeting_link, "zoom") -> %>
                                    <div class="h-8 w-8 rounded-lg">
                                      <img src={~p"/images/zoom.png"} width="36" />
                                    </div>
                                  <% event.meeting_link && String.contains?(event.meeting_link, "meet.google") -> %>
                                    <div class="h-8 w-8 rounded-lg">
                                      <img src={~p"/images/google_meet.png"} width="36" />
                                    </div>
                                  <% event.meeting_link && String.contains?(event.meeting_link, "teams") -> %>
                                    <div class="h-8 w-8 rounded-lg bg-purple-500 flex items-center justify-center shadow-sm border-2 border-purple-600">
                                      <svg
                                        class="h-5 w-5 text-white"
                                        viewBox="0 0 24 24"
                                        fill="currentColor"
                                      >
                                        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.94-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z" />
                                      </svg>
                                    </div>
                                  <% event.meeting_link -> %>
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
                            </div>
                            <span class="text-xs font-medium text-gray-600">
                              {format_datetime(event.start_time, @user_timezone)}
                            </span>
                          </div>

                          <div class="flex items-center justify-between">
                            <div class="flex flex-col space-y-2 flex-1 min-w-0">
                              <div class="flex items-center space-x-4 flex-wrap">
                                <label class="inline-flex items-center">
                                  <input
                                    type="checkbox"
                                    checked={event.notetaker_enabled}
                                    phx-click="toggle_notetaker"
                                    phx-value-event_id={event.id}
                                    class="w-4 h-4 text-green-600 border-gray-300 rounded focus:ring-green-500"
                                  />
                                  <span class="ml-2 text-sm text-gray-700">AI Notetaker</span>
                                </label>

                                <%= if event.transcript_status do %>
                                  <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium #{transcript_status_color(event.transcript_status)}"}>
                                    {String.capitalize(event.transcript_status)}
                                  </span>
                                <% end %>

                                <%= if event.attendee_count > 0 do %>
                                  <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                                    👥 {event.attendee_count} attendee{if event.attendee_count != 1,
                                      do: "s"}
                                  </span>
                                <% end %>
                              </div>

                              <%= if event.attendee_count > 0 do %>
                                <div class="w-full">
                                  <div class="mt-2 break-all">
                                    <%= for email <- event.attendee_emails do %>
                                      <span class="inline-block px-2 py-1 rounded-md text-xs bg-blue-50 text-blue-700 border border-blue-200 max-w-full break-all">
                                        {email}
                                      </span>
                                    <% end %>
                                  </div>
                                </div>
                              <% end %>
                            </div>

                            <%= if event.meeting_link do %>
                              <a
                                href={event.meeting_link}
                                target="_blank"
                                class="text-green-600 hover:text-green-700 text-sm font-medium"
                              >
                                Join →
                              </a>
                            <% end %>
                          </div>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        
    <!-- Past Events -->
        <div class="mt-8">
          <div class="bg-white border border-gray-100 rounded-xl overflow-hidden">
            <div class="px-6 py-5">
              <div class="flex items-center justify-between mb-6">
                <h3 class="text-lg font-semibold text-black">
                  Recent Past Events
                </h3>
                <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                  {length(@past_events)} events
                </span>
              </div>

              <%= if @past_events == [] do %>
                <div class="text-center py-8">
                  <div class="w-12 h-12 bg-gray-100 rounded-full flex items-center justify-center mx-auto mb-4">
                    <svg
                      class="w-6 h-6 text-gray-400"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M8 7V3a1 1 0 011-1h6a1 1 0 011 1v4h4V3a1 1 0 011-1h6a1 1 0 011 1v4h2a2 2 0 012 2v1H6V9a2 2 0 012-2h0zM6 12v24a2 2 0 002 2h32a2 2 0 002-2V12H6z"
                      />
                    </svg>
                  </div>
                  <h3 class="text-sm font-medium text-black mb-1">No past events</h3>
                  <p class="text-sm text-gray-500">
                    Past events will appear here after you sync your Google Calendar.
                  </p>
                </div>
              <% else %>
                <div class="space-y-4">
                  <%= for event <- @past_events do %>
                    <div class="border border-gray-100 rounded-lg p-4 hover:border-green-200 hover:bg-green-50 transition-all duration-200">
                      <div class="flex items-start justify-between">
                        <div class="flex-1">
                          <div class="flex items-start justify-between mb-3">
                            <div>
                              <div class="flex items-center space-x-3 mb-1">
                                <h4 class="text-sm font-semibold text-black">
                                  {event.title || "Untitled Event"}
                                </h4>
                                <%= cond do %>
                                  <% event.meeting_link && String.contains?(event.meeting_link, "zoom") -> %>
                                    <div class="h-8 w-8 rounded-lg">
                                      <img src={~p"/images/zoom.png"} width="36" />
                                    </div>
                                  <% event.meeting_link && String.contains?(event.meeting_link, "meet.google") -> %>
                                    <div class="h-8 w-8 rounded-lg">
                                      <img src={~p"/images/google_meet.png"} width="36" />
                                    </div>
                                  <% event.meeting_link && String.contains?(event.meeting_link, "teams") -> %>
                                    <div class="h-8 w-8 rounded-lg bg-purple-500 flex items-center justify-center shadow-sm border-2 border-purple-600">
                                      <svg
                                        class="h-5 w-5 text-white"
                                        viewBox="0 0 24 24"
                                        fill="currentColor"
                                      >
                                        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.94-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z" />
                                      </svg>
                                    </div>
                                  <% event.meeting_link -> %>
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
                            </div>
                            <span class="text-xs font-medium text-gray-600">
                              {format_datetime(event.start_time, @user_timezone)}
                            </span>
                          </div>

                          <div class="flex items-center justify-between">
                            <div class="flex flex-col space-y-2 flex-1 min-w-0">
                              <div class="flex items-center space-x-4 flex-wrap">
                                <%= if event.transcript_status do %>
                                  <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium #{transcript_status_color(event.transcript_status)}"}>
                                    {String.capitalize(event.transcript_status)}
                                  </span>
                                <% end %>

                                <%= if event.attendee_count > 0 do %>
                                  <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                                    👥 {event.attendee_count} attendee{if event.attendee_count != 1,
                                      do: "s"}
                                  </span>
                                <% end %>

                                <%= if length(event.social_posts) > 0 do %>
                                  <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                                    📱 {length(event.social_posts)} Post(s)
                                  </span>
                                <% end %>
                              </div>

                              <%= if event.attendee_count > 0 do %>
                                <div class="w-full">
                                  <div class="mt-2 max-h-24 overflow-y-auto">
                                    <%= for email <- event.attendee_emails do %>
                                      <span class="inline-block px-2 py-1 my-1 rounded-md text-xs bg-blue-50 text-blue-700 border border-blue-200 break-all max-w-full">
                                        {email}
                                      </span>
                                    <% end %>
                                  </div>
                                </div>
                              <% end %>
                            </div>

                            <div class="flex items-center space-x-3">
                              <%= if event.notetaker_enabled do %>
                                <button
                                  phx-click="reprocess_automation"
                                  phx-value-event_id={event.id}
                                  disabled={@reprocessing_event_id == event.id}
                                  class={[
                                    "inline-flex items-center px-3 py-1 border border-gray-300 shadow-sm text-xs font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500",
                                    if(@reprocessing_event_id == event.id,
                                      do: "opacity-50 cursor-not-allowed"
                                    )
                                  ]}
                                  title={
                                    if @reprocessing_event_id == event.id,
                                      do: "Reprocessing automation...",
                                      else: "Reprocess automation for this meeting"
                                  }
                                >
                                  <%= if @reprocessing_event_id == event.id do %>
                                    <svg
                                      class="animate-spin w-3 h-3 mr-1"
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
                                    Reprocessing...
                                  <% else %>
                                    <svg
                                      class="w-3 h-3 mr-1"
                                      fill="none"
                                      stroke="currentColor"
                                      viewBox="0 0 24 24"
                                    >
                                      <path
                                        stroke-linecap="round"
                                        stroke-linejoin="round"
                                        stroke-width="2"
                                        d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                                      >
                                      </path>
                                    </svg>
                                    Reprocess
                                  <% end %>
                                </button>
                              <% end %>

                              <.link
                                href={"/meetings/#{event.id}"}
                                class="text-green-600 hover:text-green-700 text-sm font-medium"
                              >
                                View Details →
                              </.link>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
                
    <!-- View All Past Events Link -->
                <div class="mt-6 text-center">
                  <.link
                    href="/meetings"
                    class="inline-flex items-center px-4 py-2 border border-green-300 shadow-sm text-sm font-medium rounded-md text-green-700 bg-white hover:bg-green-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                  >
                    View All Past Meetings
                  </.link>
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
  defp transcript_status_color("failed"), do: "bg-red-100 text-red-800"
  defp transcript_status_color(_), do: "bg-gray-100 text-gray-800"
end
