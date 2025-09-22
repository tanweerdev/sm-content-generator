defmodule SMGWeb.SettingsLive do
  use SMGWeb, :live_view

  alias SMG.{Accounts, Settings}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:user, user)
      |> assign(:active_tab, "oauth")
      |> assign(:saving, false)
      |> load_settings()

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
    {:noreply, push_patch(socket, to: "/settings?tab=#{tab}")}
  end

  @impl true
  def handle_event("connect_linkedin", _params, socket) do
    {:noreply, redirect(socket, external: "/auth/linkedin/custom")}
  end

  @impl true
  def handle_event("connect_facebook", _params, socket) do
    {:noreply, redirect(socket, external: "/auth/facebook")}
  end

  @impl true
  def handle_event("connect_google", _params, socket) do
    {:noreply, redirect(socket, external: "/auth/google")}
  end

  @impl true
  def handle_event("disconnect_google", %{"account_id" => account_id}, socket) do
    case Accounts.get_google_account(account_id) do
      nil ->
        socket = put_flash(socket, :error, "Google account not found")
        {:noreply, socket}

      google_account ->
        # Check if this account belongs to the current user
        if google_account.user_id == socket.assigns.user.id do
          case Accounts.delete_google_account(google_account) do
            {:ok, _} ->
              socket =
                socket
                |> put_flash(:info, "Google account disconnected successfully")
                |> load_settings()

              {:noreply, socket}

            {:error, _} ->
              socket = put_flash(socket, :error, "Failed to disconnect Google account")
              {:noreply, socket}
          end
        else
          socket = put_flash(socket, :error, "Unauthorized")
          {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_event("disconnect_platform", %{"platform" => platform}, socket) do
    user = socket.assigns.user

    case Settings.disconnect_social_platform(user, platform) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "#{String.capitalize(platform)} account disconnected successfully!")
          |> load_settings()

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, "Failed to disconnect account: #{reason}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_bot_timing", %{"minutes" => minutes}, socket) do
    user = socket.assigns.user
    bot_settings = %{join_minutes_before: String.to_integer(minutes)}

    socket = assign(socket, :saving, true)

    case Settings.update_bot_settings(user, bot_settings) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:saving, false)
          |> load_settings()

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:saving, false)
          |> put_flash(:error, "Failed to save settings: #{reason}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_bot_settings", params, socket) do
    user = socket.assigns.user
    bot_settings = extract_bot_settings(params)

    socket = assign(socket, :saving, true)

    case Settings.update_bot_settings(user, bot_settings) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:saving, false)
          |> put_flash(:info, "Bot settings saved successfully!")
          |> load_settings()

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:saving, false)
          |> put_flash(:error, "Failed to save settings: #{reason}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_automation", params, socket) do
    user = socket.assigns.user
    automation_params = extract_automation_params(params)

    case Settings.create_or_update_automation(user, automation_params) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Automation saved successfully!")
          |> load_settings()

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, "Failed to save automation: #{reason}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_automation", %{"id" => automation_id}, socket) do
    case Settings.delete_automation(automation_id) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Automation deleted successfully!")
          |> load_settings()

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, "Failed to delete automation: #{reason}")

        {:noreply, socket}
    end
  end

  defp load_settings(socket) do
    user = socket.assigns.user

    socket
    |> assign(:connected_platforms, Settings.get_connected_platforms(user))
    |> assign(:bot_settings, Settings.get_bot_settings(user))
    |> assign(:automations, Settings.list_automations(user))
    |> assign(:google_accounts, Accounts.list_user_google_accounts(user))
  end

  defp extract_bot_settings(params) do
    %{
      join_minutes_before: String.to_integer(params["join_minutes_before"] || "5")
    }
  end

  defp extract_automation_params(params) do
    %{
      name: params["name"],
      platform: params["platform"],
      content_type: params["content_type"],
      prompt_template: params["prompt_template"],
      enabled: params["enabled"] == "true",
      auto_publish: params["auto_publish"] == "true"
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-gray-50 via-blue-50 to-indigo-100">
      <!-- Navigation -->
      <.navbar current_user={@user} />
      
    <!-- Flash Messages -->
      <SMGWeb.Layouts.flash_group flash={@flash} />
      
    <!-- Main Content -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Header -->
        <div class="mb-10">
          <nav class="flex mb-6" aria-label="Breadcrumb">
            <ol class="flex items-center space-x-4">
              <li>
                <div>
                  <.link
                    href="/dashboard"
                    class="text-gray-500 hover:text-gray-700 font-medium transition-colors"
                  >
                    Dashboard
                  </.link>
                </div>
              </li>
              <li>
                <div class="flex items-center">
                  <svg
                    class="flex-shrink-0 h-5 w-5 text-gray-300 mx-3"
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
                  <span class="text-sm font-medium text-gray-700">Settings</span>
                </div>
              </li>
            </ol>
          </nav>

          <div class="text-center">
            <div class="inline-flex items-center justify-center w-16 h-16 bg-gradient-to-br from-blue-500 to-purple-600 rounded-2xl shadow-lg mb-4">
              <svg class="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
                />
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                />
              </svg>
            </div>
            <h1 class="text-4xl font-bold bg-gradient-to-r from-gray-900 via-blue-800 to-purple-800 bg-clip-text text-transparent mb-3">
              Settings
            </h1>
            <p class="text-lg text-gray-600 max-w-2xl mx-auto">
              Manage your integrations and configure your content generation platform
            </p>
          </div>
        </div>
        
    <!-- Tabs -->
        <div class="mb-10">
          <div class="flex justify-center">
            <div class="bg-white/60 backdrop-blur-sm rounded-2xl p-2 shadow-lg border border-white/20">
              <nav class="flex space-x-2" aria-label="Tabs">
                <button
                  phx-click="switch_tab"
                  phx-value-tab="oauth"
                  class={"#{if @active_tab == "oauth", do: "bg-white text-blue-600 shadow-md", else: "text-gray-600 hover:text-gray-900 hover:bg-white/50"} px-6 py-3 text-sm font-semibold rounded-xl transition-all duration-200 flex items-center space-x-2"}
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"
                    />
                  </svg>
                  <span>Social Media</span>
                </button>
                <button
                  phx-click="switch_tab"
                  phx-value-tab="bot"
                  class={"#{if @active_tab == "bot", do: "bg-white text-blue-600 shadow-md", else: "text-gray-600 hover:text-gray-900 hover:bg-white/50"} px-6 py-3 text-sm font-semibold rounded-xl transition-all duration-200 flex items-center space-x-2"}
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                    />
                  </svg>
                  <span>Bot Settings</span>
                </button>
                <button
                  phx-click="switch_tab"
                  phx-value-tab="automations"
                  class={"#{if @active_tab == "automations", do: "bg-white text-blue-600 shadow-md", else: "text-gray-600 hover:text-gray-900 hover:bg-white/50"} px-6 py-3 text-sm font-semibold rounded-xl transition-all duration-200 flex items-center space-x-2"}
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
                    />
                  </svg>
                  <span>Automations</span>
                </button>
                <button
                  phx-click="switch_tab"
                  phx-value-tab="google"
                  class={"#{if @active_tab == "google", do: "bg-white text-blue-600 shadow-md", else: "text-gray-600 hover:text-gray-900 hover:bg-white/50"} px-6 py-3 text-sm font-semibold rounded-xl transition-all duration-200 flex items-center space-x-2"}
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M8 7v8a2 2 0 002 2h6M8 7V5a2 2 0 012-2h4.586a1 1 0 01.707.293l4.414 4.414a1 1 0 01.293.707V15a2 2 0 01-2 2h-2M8 7H6a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2v-2"
                    />
                  </svg>
                  <span>Google Calendar</span>
                </button>
              </nav>
            </div>
          </div>
        </div>
        
    <!-- Tab Content -->
        <%= case @active_tab do %>
          <% "oauth" -> %>
            <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
              <!-- LinkedIn Connection -->
              <div class="relative group">
                <div class="absolute -inset-0.5 bg-gradient-to-r from-blue-600 to-purple-600 rounded-xl blur opacity-20 group-hover:opacity-40 transition duration-1000 group-hover:duration-200">
                </div>
                <div class="relative bg-white rounded-xl shadow-lg border border-gray-100 hover:shadow-xl transition-all duration-300 overflow-hidden">
                  <div class="p-6">
                    <div class="flex items-start justify-between">
                      <div class="flex items-start space-x-4">
                        <div class="flex-shrink-0">
                          <div class="h-12 w-12 rounded-xl bg-gradient-to-br from-blue-500 to-blue-600 flex items-center justify-center shadow-lg">
                            <svg class="h-7 w-7 text-white" fill="currentColor" viewBox="0 0 24 24">
                              <path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z" />
                            </svg>
                          </div>
                        </div>
                        <div class="flex-1 min-w-0">
                          <div class="flex items-center space-x-2 mb-2">
                            <h3 class="text-xl font-bold text-gray-900">LinkedIn</h3>
                            <%= if Map.get(@connected_platforms, "linkedin") do %>
                              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                                <div class="w-1.5 h-1.5 bg-green-500 rounded-full mr-1"></div>
                                Connected
                              </span>
                            <% end %>
                          </div>
                          <p class="text-sm text-gray-600 leading-relaxed">
                            <%= if Map.get(@connected_platforms, "linkedin") do %>
                              Connected as
                              <span class="font-medium text-gray-900">
                                {Map.get(@connected_platforms, "linkedin").email}
                              </span>
                            <% else %>
                              Connect your LinkedIn account to automatically share your meeting insights and professional content.
                            <% end %>
                          </p>
                        </div>
                      </div>
                    </div>
                    <div class="mt-6 flex justify-end">
                      <%= if Map.get(@connected_platforms, "linkedin") do %>
                        <button
                          phx-click="disconnect_platform"
                          phx-value-platform="linkedin"
                          style="background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); color: white; padding: 10px 20px; border: none; border-radius: 8px; font-weight: 600; cursor: pointer; box-shadow: 0 4px 12px rgba(239, 68, 68, 0.3); transition: all 0.2s ease;"
                          onmouseover="this.style.transform='translateY(-1px)'; this.style.boxShadow='0 6px 16px rgba(239, 68, 68, 0.4)'"
                          onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='0 4px 12px rgba(239, 68, 68, 0.3)'"
                        >
                          Disconnect
                        </button>
                      <% else %>
                        <button
                          phx-click="connect_linkedin"
                          style="background: linear-gradient(135deg, #0077b5 0%, #005885 100%); color: white; padding: 12px 24px; border: none; border-radius: 8px; font-weight: 600; cursor: pointer; box-shadow: 0 4px 12px rgba(0, 119, 181, 0.3); transition: all 0.2s ease;"
                          onmouseover="this.style.transform='translateY(-1px)'; this.style.boxShadow='0 6px 16px rgba(0, 119, 181, 0.4)'"
                          onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='0 4px 12px rgba(0, 119, 181, 0.3)'"
                        >
                          Connect LinkedIn
                        </button>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
              
    <!-- Facebook Connection -->
              <div class="relative group">
                <div class="absolute -inset-0.5 bg-gradient-to-r from-blue-500 to-indigo-600 rounded-xl blur opacity-20 group-hover:opacity-40 transition duration-1000 group-hover:duration-200">
                </div>
                <div class="relative bg-white rounded-xl shadow-lg border border-gray-100 hover:shadow-xl transition-all duration-300 overflow-hidden">
                  <div class="p-6">
                    <div class="flex items-start justify-between">
                      <div class="flex items-start space-x-4">
                        <div class="flex-shrink-0">
                          <div class="h-12 w-12 rounded-xl bg-gradient-to-br from-blue-600 to-indigo-600 flex items-center justify-center shadow-lg">
                            <svg class="h-7 w-7 text-white" fill="currentColor" viewBox="0 0 24 24">
                              <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z" />
                            </svg>
                          </div>
                        </div>
                        <div class="flex-1 min-w-0">
                          <div class="flex items-center space-x-2 mb-2">
                            <h3 class="text-xl font-bold text-gray-900">Facebook</h3>
                            <%= if Map.get(@connected_platforms, "facebook") do %>
                              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                                <div class="w-1.5 h-1.5 bg-green-500 rounded-full mr-1"></div>
                                Connected
                              </span>
                            <% end %>
                          </div>
                          <p class="text-sm text-gray-600 leading-relaxed">
                            <%= if Map.get(@connected_platforms, "facebook") do %>
                              Connected as
                              <span class="font-medium text-gray-900">
                                {Map.get(@connected_platforms, "facebook").email}
                              </span>
                            <% else %>
                              Connect your Facebook account to automatically share content and engage with your audience.
                            <% end %>
                          </p>
                        </div>
                      </div>
                    </div>
                    <div class="mt-6 flex justify-end">
                      <%= if Map.get(@connected_platforms, "facebook") do %>
                        <button
                          phx-click="disconnect_platform"
                          phx-value-platform="facebook"
                          style="background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); color: white; padding: 10px 20px; border: none; border-radius: 8px; font-weight: 600; cursor: pointer; box-shadow: 0 4px 12px rgba(239, 68, 68, 0.3); transition: all 0.2s ease;"
                          onmouseover="this.style.transform='translateY(-1px)'; this.style.boxShadow='0 6px 16px rgba(239, 68, 68, 0.4)'"
                          onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='0 4px 12px rgba(239, 68, 68, 0.3)'"
                        >
                          Disconnect
                        </button>
                      <% else %>
                        <button
                          phx-click="connect_facebook"
                          style="background: linear-gradient(135deg, #1877f2 0%, #166fe5 100%); color: white; padding: 12px 24px; border: none; border-radius: 8px; font-weight: 600; cursor: pointer; box-shadow: 0 4px 12px rgba(24, 119, 242, 0.3); transition: all 0.2s ease;"
                          onmouseover="this.style.transform='translateY(-1px)'; this.style.boxShadow='0 6px 16px rgba(24, 119, 242, 0.4)'"
                          onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='0 4px 12px rgba(24, 119, 242, 0.3)'"
                        >
                          Connect Facebook
                        </button>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
              
    <!-- Coming Soon Card -->
              <div class="relative group lg:col-span-2">
                <div class="absolute -inset-0.5 bg-gradient-to-r from-gray-200 to-gray-300 rounded-xl blur opacity-20">
                </div>
                <div class="relative bg-gray-50 rounded-xl border-2 border-dashed border-gray-200 hover:border-gray-300 transition-all duration-300">
                  <div class="p-6 text-center">
                    <div class="flex justify-center mb-4">
                      <div class="h-12 w-12 rounded-xl bg-gray-200 flex items-center justify-center">
                        <svg
                          class="h-6 w-6 text-gray-400"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M12 6v6m0 0v6m0-6h6m-6 0H6"
                          />
                        </svg>
                      </div>
                    </div>
                    <h3 class="text-lg font-semibold text-gray-900 mb-2">
                      More Platforms Coming Soon
                    </h3>
                    <p class="text-sm text-gray-500">
                      Instagram, TikTok, and more social platforms will be available soon.
                    </p>
                  </div>
                </div>
              </div>
            </div>
          <% "bot" -> %>
            <div class="max-w-4xl mx-auto">
              <div class="relative group">
                <div class="absolute -inset-0.5 bg-gradient-to-r from-purple-600 to-pink-600 rounded-xl blur opacity-20 group-hover:opacity-40 transition duration-1000 group-hover:duration-200">
                </div>
                <div class="relative bg-white rounded-xl shadow-lg border border-gray-100 overflow-hidden">
                  <div class="bg-gradient-to-r from-purple-500 to-pink-500 px-8 py-6">
                    <div class="flex items-center space-x-3">
                      <div class="h-12 w-12 bg-white/20 rounded-xl flex items-center justify-center">
                        <svg
                          class="h-7 w-7 text-white"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                          />
                        </svg>
                      </div>
                      <div>
                        <h3 class="text-2xl font-bold text-white">AI Bot Meeting Join time</h3>
                        <p class="text-purple-100">
                          Configure how many minutes before the meeting start time your AI bot should join
                        </p>
                      </div>
                    </div>
                  </div>

                  <div class="p-8">
                    <div class="space-y-8">
                      <!-- Join Timing Section -->
                      <div class="bg-gray-50 rounded-xl p-6 border border-gray-100">
                        <div class="flex items-start space-x-4">
                          <div class="h-10 w-10 bg-blue-100 rounded-xl flex items-center justify-center flex-shrink-0 mt-1">
                            <svg
                              class="h-5 w-5 text-blue-600"
                              fill="none"
                              stroke="currentColor"
                              viewBox="0 0 24 24"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                stroke-width="2"
                                d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                              />
                            </svg>
                          </div>
                          <div class="flex-1">
                            <label
                              for="join_minutes_before"
                              class="block text-lg font-semibold text-gray-900 mb-2"
                            >
                              Meeting Join Timing
                            </label>
                            <p class="text-sm text-gray-600 mb-4">
                              Choose how many minutes before the meeting start time the AI bot should join. Settings save automatically.
                            </p>

                            <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
                              <%= for minutes <- [1, 2, 3, 5, 10, 15] do %>
                                <label class="relative">
                                  <input
                                    type="radio"
                                    name="join_minutes_before"
                                    value={minutes}
                                    checked={@bot_settings.join_minutes_before == minutes}
                                    phx-click="update_bot_timing"
                                    phx-value-minutes={minutes}
                                    class="sr-only peer"
                                  />
                                  <div class={"p-4 border-2 rounded-xl cursor-pointer transition-all duration-200 relative #{if @bot_settings.join_minutes_before == minutes, do: "border-purple-500 bg-purple-50 shadow-lg", else: "border-gray-200 hover:border-purple-300 hover:bg-purple-25"}"}>
                                    <%= if @bot_settings.join_minutes_before == minutes do %>
                                      <div class="absolute -top-2 -right-2 h-6 w-6 bg-purple-500 rounded-full flex items-center justify-center">
                                        <svg
                                          class="h-3 w-3 text-white"
                                          fill="none"
                                          stroke="currentColor"
                                          viewBox="0 0 24 24"
                                        >
                                          <path
                                            stroke-linecap="round"
                                            stroke-linejoin="round"
                                            stroke-width="3"
                                            d="M5 13l4 4L19 7"
                                          />
                                        </svg>
                                      </div>
                                      <div class="absolute inset-0 bg-purple-500 rounded-xl opacity-10">
                                      </div>
                                    <% end %>
                                    <div class="text-center relative">
                                      <div class={"text-2xl font-bold transition-colors #{if @bot_settings.join_minutes_before == minutes, do: "text-purple-600", else: "text-gray-900"}"}>
                                        {minutes}
                                      </div>
                                      <div class={"text-sm transition-colors #{if @bot_settings.join_minutes_before == minutes, do: "text-purple-600", else: "text-gray-600"}"}>
                                        minute{if minutes != 1, do: "s"}
                                      </div>
                                      <%= if @bot_settings.join_minutes_before == minutes do %>
                                        <div class="absolute -bottom-1 left-1/2 transform -translate-x-1/2">
                                          <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-purple-500 text-white">
                                            Active
                                          </span>
                                        </div>
                                      <% end %>
                                    </div>
                                  </div>
                                </label>
                              <% end %>
                            </div>
                            
    <!-- Auto-save Status -->
                            <%= if @saving do %>
                              <div class="mt-4 p-3 bg-purple-50 rounded-lg border border-purple-200">
                                <div class="flex items-center space-x-2">
                                  <svg
                                    class="animate-spin h-4 w-4 text-purple-600"
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
                                  <p class="text-sm text-purple-800 font-medium">
                                    Saving settings...
                                  </p>
                                </div>
                              </div>
                            <% end %>

                            <div class="mt-4 p-4 bg-blue-50 rounded-lg border border-blue-200">
                              <div class="flex items-center space-x-2">
                                <svg
                                  class="h-5 w-5 text-blue-600"
                                  fill="none"
                                  stroke="currentColor"
                                  viewBox="0 0 24 24"
                                >
                                  <path
                                    stroke-linecap="round"
                                    stroke-linejoin="round"
                                    stroke-width="2"
                                    d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                                  />
                                </svg>
                                <p class="text-sm text-blue-800">
                                  <strong>Recommended:</strong>
                                  5 minutes allows time for the bot to join and start recording without missing content.
                                </p>
                              </div>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% "automations" -> %>
            <div class="max-w-6xl mx-auto space-y-8">
              <!-- Existing Automations -->
              <%= if length(@automations) > 0 do %>
                <div class="relative group">
                  <div class="absolute -inset-0.5 bg-gradient-to-r from-green-600 to-teal-600 rounded-xl blur opacity-20 group-hover:opacity-40 transition duration-1000 group-hover:duration-200">
                  </div>
                  <div class="relative bg-white rounded-xl shadow-lg border border-gray-100 overflow-hidden">
                    <div class="bg-gradient-to-r from-green-500 to-teal-500 px-8 py-6">
                      <div class="flex items-center justify-between">
                        <div class="flex items-center space-x-3">
                          <div class="h-12 w-12 bg-white/20 rounded-xl flex items-center justify-center">
                            <svg
                              class="h-7 w-7 text-white"
                              fill="none"
                              stroke="currentColor"
                              viewBox="0 0 24 24"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                stroke-width="2"
                                d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
                              />
                            </svg>
                          </div>
                          <div>
                            <h3 class="text-2xl font-bold text-white">Active Automations</h3>
                            <p class="text-green-100">Manage your content generation workflows</p>
                          </div>
                        </div>
                        <div class="text-white/80 text-sm">
                          {length(@automations)} automation{if length(@automations) != 1, do: "s"}
                        </div>
                      </div>
                    </div>

                    <div class="p-8">
                      <div class="grid gap-6">
                        <%= for automation <- @automations do %>
                          <div class="border border-gray-200 rounded-xl p-6 hover:shadow-md transition-shadow duration-200 bg-gray-50">
                            <div class="flex items-center justify-between">
                              <div class="flex-1">
                                <div class="flex items-center space-x-3 mb-3">
                                  <h4 class="text-lg font-semibold text-gray-900">
                                    {automation.name}
                                  </h4>
                                  <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                                    {String.capitalize(automation.platform)}
                                  </span>
                                  <span class={"inline-flex items-center px-3 py-1 rounded-full text-xs font-medium #{if automation.enabled, do: "bg-green-100 text-green-800", else: "bg-gray-100 text-gray-800"}"}>
                                    <div class={"w-2 h-2 #{if automation.enabled, do: "bg-green-500", else: "bg-gray-400"} rounded-full mr-2"}>
                                    </div>
                                    {if automation.enabled, do: "Active", else: "Inactive"}
                                  </span>
                                  <%= if automation.auto_publish do %>
                                    <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                                      <div class="w-2 h-2 bg-blue-500 rounded-full mr-2"></div>
                                      Auto-Publish
                                    </span>
                                  <% else %>
                                    <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
                                      <div class="w-2 h-2 bg-yellow-500 rounded-full mr-2"></div>
                                      Draft Only
                                    </span>
                                  <% end %>
                                </div>
                                <p class="text-sm text-gray-600 mb-2">
                                  <strong>Content Type:</strong> {automation.content_type}
                                </p>
                                <%= if automation.prompt_template && automation.prompt_template != "" do %>
                                  <p class="text-xs text-gray-500 bg-white rounded p-2 border">
                                    {String.slice(automation.prompt_template, 0, 120)}{if String.length(
                                                                                            automation.prompt_template
                                                                                          ) > 120,
                                                                                          do: "..."}
                                  </p>
                                <% end %>
                              </div>
                              <button
                                phx-click="delete_automation"
                                phx-value-id={automation.id}
                                data-confirm="Are you sure you want to delete this automation?"
                                class="ml-4 p-2 text-red-600 hover:text-red-800 hover:bg-red-50 rounded-lg transition-colors"
                                title="Delete automation"
                              >
                                <svg
                                  class="h-5 w-5"
                                  fill="none"
                                  stroke="currentColor"
                                  viewBox="0 0 24 24"
                                >
                                  <path
                                    stroke-linecap="round"
                                    stroke-linejoin="round"
                                    stroke-width="2"
                                    d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                                  />
                                </svg>
                              </button>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
              
    <!-- Create New Automation -->
              <div class="relative group">
                <div class="absolute -inset-0.5 bg-gradient-to-r from-indigo-600 to-purple-600 rounded-xl blur opacity-20 group-hover:opacity-40 transition duration-1000 group-hover:duration-200">
                </div>
                <div class="relative bg-white rounded-xl shadow-lg border border-gray-100 overflow-hidden">
                  <div class="bg-gradient-to-r from-indigo-500 to-purple-500 px-8 py-6">
                    <div class="flex items-center space-x-3">
                      <div class="h-12 w-12 bg-white/20 rounded-xl flex items-center justify-center">
                        <svg
                          class="h-7 w-7 text-white"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M12 6v6m0 0v6m0-6h6m-6 0H6"
                          />
                        </svg>
                      </div>
                      <div>
                        <h3 class="text-2xl font-bold text-white">Create New Automation</h3>
                        <p class="text-indigo-100">
                          Set up automated content generation for your meetings
                        </p>
                      </div>
                    </div>
                  </div>

                  <div class="p-8">
                    <form phx-submit="save_automation">
                      <div class="space-y-8">
                        <!-- Basic Info Section -->
                        <div class="bg-gray-50 rounded-xl p-6 border border-gray-100">
                          <h4 class="text-lg font-semibold text-gray-900 mb-4 flex items-center">
                            <svg
                              class="h-5 w-5 text-indigo-600 mr-2"
                              fill="none"
                              stroke="currentColor"
                              viewBox="0 0 24 24"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                stroke-width="2"
                                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                              />
                            </svg>
                            Basic Information
                          </h4>
                          <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
                            <div>
                              <label for="name" class="block text-sm font-semibold text-gray-700 mb-2">
                                Automation Name
                              </label>
                              <input
                                type="text"
                                id="name"
                                name="name"
                                placeholder="e.g., LinkedIn Professional Updates"
                                class="block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm px-4 py-3"
                                required
                              />
                              <p class="mt-1 text-xs text-gray-500">
                                Choose a descriptive name for this automation
                              </p>
                            </div>

                            <div>
                              <label
                                for="platform"
                                class="block text-sm font-semibold text-gray-700 mb-2"
                              >
                                Target Platform
                              </label>
                              <select
                                id="platform"
                                name="platform"
                                class="block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm px-4 py-3"
                                required
                              >
                                <option value="">Choose platform...</option>
                                <option value="linkedin">📘 LinkedIn</option>
                                <option value="facebook">📱 Facebook</option>
                              </select>
                              <p class="mt-1 text-xs text-gray-500">
                                Where should the content be published?
                              </p>
                            </div>
                          </div>
                        </div>
                        
    <!-- Content Configuration -->
                        <div class="bg-blue-50 rounded-xl p-6 border border-blue-100">
                          <h4 class="text-lg font-semibold text-gray-900 mb-4 flex items-center">
                            <svg
                              class="h-5 w-5 text-blue-600 mr-2"
                              fill="none"
                              stroke="currentColor"
                              viewBox="0 0 24 24"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                stroke-width="2"
                                d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                              />
                            </svg>
                            Content Configuration
                          </h4>

                          <div class="mb-6">
                            <label
                              for="content_type"
                              class="block text-sm font-semibold text-gray-700 mb-3"
                            >
                              Content Type
                            </label>
                            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                              <%= for {value, label, description} <- [
                                {"marketing", "Marketing Content", "Promotional posts about meeting outcomes"},
                                {"educational", "Educational Content", "Knowledge sharing and lessons learned"},
                                {"insights", "Key Insights", "Important takeaways and discoveries"},
                                {"summary", "Meeting Summary", "Brief overview of meeting topics"},
                                {"takeaways", "Action Items", "Next steps and responsibilities"}
                              ] do %>
                                <label class="relative">
                                  <input
                                    type="radio"
                                    name="content_type"
                                    value={value}
                                    class="sr-only peer"
                                    required
                                  />
                                  <div class="p-4 border-2 border-gray-200 rounded-xl cursor-pointer transition-all duration-200 peer-checked:border-indigo-500 peer-checked:bg-indigo-50 hover:border-indigo-300">
                                    <div class="text-sm font-medium text-gray-900 mb-1">{label}</div>
                                    <div class="text-xs text-gray-600">{description}</div>
                                  </div>
                                </label>
                              <% end %>
                            </div>
                          </div>

                          <div>
                            <label
                              for="prompt_template"
                              class="block text-sm font-semibold text-gray-700 mb-2"
                            >
                              Custom Prompt Template (Optional)
                            </label>
                            <textarea
                              id="prompt_template"
                              name="prompt_template"
                              rows="4"
                              placeholder="Create engaging {content_type} content for {platform} based on this meeting transcript. Focus on actionable insights and professional tone. Include relevant hashtags..."
                              class="block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm px-4 py-3"
                            ></textarea>
                            <div class="mt-2 p-3 bg-blue-100 rounded-lg border border-blue-200">
                              <p class="text-xs text-blue-800">
                                <strong>Available placeholders:</strong>
                                &#123;content_type&#125;, &#123;platform&#125;, &#123;meeting_title&#125;, &#123;meeting_date&#125;
                              </p>
                            </div>
                          </div>
                        </div>
                        
    <!-- Settings -->
                        <div class="bg-green-50 rounded-xl p-6 border border-green-100">
                          <h4 class="text-lg font-semibold text-gray-900 mb-4 flex items-center">
                            <svg
                              class="h-5 w-5 text-green-600 mr-2"
                              fill="none"
                              stroke="currentColor"
                              viewBox="0 0 24 24"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                stroke-width="2"
                                d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
                              />
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                stroke-width="2"
                                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                              />
                            </svg>
                            Automation Settings
                          </h4>

                          <div class="space-y-4">
                            <div class="flex items-center p-4 bg-white rounded-lg border border-green-200">
                              <input
                                id="enabled"
                                name="enabled"
                                type="checkbox"
                                value="true"
                                checked
                                class="h-5 w-5 text-green-600 focus:ring-green-500 border-gray-300 rounded"
                              />
                              <div class="ml-3">
                                <label for="enabled" class="text-sm font-medium text-gray-900">
                                  Enable this automation immediately
                                </label>
                                <p class="text-xs text-gray-600">
                                  Start generating content automatically for new meetings
                                </p>
                              </div>
                            </div>

                            <div class="flex items-center p-4 bg-blue-50 rounded-lg border border-blue-200">
                              <input
                                id="auto_publish"
                                name="auto_publish"
                                type="checkbox"
                                value="true"
                                class="h-5 w-5 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                              />
                              <div class="ml-3">
                                <label for="auto_publish" class="text-sm font-medium text-gray-900">
                                  Automatically publish to social media
                                </label>
                                <p class="text-xs text-gray-600">
                                  Posts will be published immediately after generation. If unchecked, posts will be saved as drafts for manual review.
                                </p>
                              </div>
                            </div>
                          </div>
                        </div>
                        
    <!-- Action Buttons -->
                        <div class="flex justify-between items-center pt-6 border-t border-gray-200">
                          <div class="text-sm text-gray-500">
                            💡 Tip: You can always edit or disable automations later
                          </div>
                          <button
                            type="submit"
                            style="background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%); color: white; padding: 12px 32px; border: none; border-radius: 12px; font-weight: 600; cursor: pointer; box-shadow: 0 4px 12px rgba(99, 102, 241, 0.3); transition: all 0.2s ease;"
                            onmouseover="this.style.transform='translateY(-1px)'; this.style.boxShadow='0 6px 16px rgba(99, 102, 241, 0.4)'"
                            onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='0 4px 12px rgba(99, 102, 241, 0.3)'"
                          >
                            <div class="flex items-center space-x-2">
                              <svg
                                class="h-4 w-4"
                                fill="none"
                                stroke="currentColor"
                                viewBox="0 0 24 24"
                              >
                                <path
                                  stroke-linecap="round"
                                  stroke-linejoin="round"
                                  stroke-width="2"
                                  d="M13 10V3L4 14h7v7l9-11h-7z"
                                />
                              </svg>
                              <span>Create Automation</span>
                            </div>
                          </button>
                        </div>
                      </div>
                    </form>
                  </div>
                </div>
              </div>
            </div>
          <% "google" -> %>
            <div class="max-w-6xl mx-auto space-y-8">
              <!-- Connected Google Accounts -->
              <%= if length(@google_accounts) > 0 do %>
                <div class="relative group">
                  <div class="absolute -inset-0.5 bg-gradient-to-r from-red-600 to-orange-600 rounded-xl blur opacity-20 group-hover:opacity-40 transition duration-1000 group-hover:duration-200">
                  </div>
                  <div class="relative bg-white rounded-xl shadow-lg border border-gray-100 overflow-hidden">
                    <div class="bg-gradient-to-r from-red-500 to-orange-500 px-8 py-6">
                      <div class="flex items-center justify-between">
                        <div class="flex items-center space-x-3">
                          <div class="h-12 w-12 bg-white/20 rounded-xl flex items-center justify-center">
                            <svg
                              class="h-7 w-7 text-white"
                              fill="none"
                              stroke="currentColor"
                              viewBox="0 0 24 24"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                stroke-width="2"
                                d="M8 7v8a2 2 0 002 2h6M8 7V5a2 2 0 012-2h4.586a1 1 0 01.707.293l4.414 4.414a1 1 0 01.293.707V15a2 2 0 01-2 2h-2M8 7H6a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2v-2"
                              />
                            </svg>
                          </div>
                          <div>
                            <h3 class="text-2xl font-bold text-white">Connected Google Accounts</h3>
                            <p class="text-red-100">Manage your Google Calendar integrations</p>
                          </div>
                        </div>
                        <div class="text-white/80 text-sm">
                          {length(@google_accounts)} account{if length(@google_accounts) != 1, do: "s"}
                        </div>
                      </div>
                    </div>

                    <div class="p-8">
                      <div class="grid gap-6">
                        <%= for account <- @google_accounts do %>
                          <div class="border border-gray-200 rounded-xl p-6 hover:shadow-md transition-shadow duration-200 bg-gray-50">
                            <div class="flex items-center justify-between">
                              <div class="flex items-center space-x-4">
                                <div class="h-3 w-3 rounded-lg bg-gradient-to-br from-red-500 to-orange-500 flex items-center justify-center shadow-md">
                                  <svg
                                    class="h-5 w-5 text-white"
                                    fill="currentColor"
                                    viewBox="0 0 24 24"
                                  >
                                    <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                                    <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                                    <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
                                    <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
                                  </svg>
                                </div>
                                <div class="flex-1">
                                  <h4 class="text-lg font-semibold text-gray-900 mb-1">
                                    {account.email}
                                  </h4>
                                  <div class="flex items-center space-x-3">
                                    <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                                      <div class="w-1.5 h-1.5 bg-green-500 rounded-full mr-1"></div>
                                      Connected
                                    </span>
                                    <%= if account.scope do %>
                                      <span class="text-xs text-gray-500">
                                        Scopes: {String.slice(account.scope, 0, 50)}{if String.length(
                                                                                          account.scope
                                                                                        ) > 50,
                                                                                        do: "..."}
                                      </span>
                                    <% end %>
                                  </div>
                                  <%= if account.expires_at do %>
                                    <p class="text-xs text-gray-500 mt-1">
                                      Token expires: {Calendar.strftime(
                                        account.expires_at,
                                        "%B %d, %Y at %I:%M %p"
                                      )}
                                    </p>
                                  <% end %>
                                </div>
                              </div>
                              <%= if account.email != @user.email do %>
                                <button
                                  phx-click="disconnect_google"
                                  phx-value-account_id={account.id}
                                  data-confirm="Are you sure you want to disconnect this Google account? This will remove access to calendar events from this account."
                                  class="inline-flex items-center px-3 py-2 border border-red-300 shadow-sm text-sm font-medium rounded-md text-red-700 bg-white hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                                  title="Disconnect Google account"
                                >
                                  <svg
                                    class="w-4 h-4 mr-1"
                                    fill="none"
                                    stroke="currentColor"
                                    viewBox="0 0 24 24"
                                  >
                                    <path
                                      stroke-linecap="round"
                                      stroke-linejoin="round"
                                      stroke-width="2"
                                      d="M6 18L18 6M6 6l12 12"
                                    />
                                  </svg>
                                  Disconnect
                                </button>
                              <% else %>
                                <span class="inline-flex items-center px-3 py-2 border border-green-300 shadow-sm text-sm font-medium rounded-md text-green-700 bg-green-50">
                                  <svg
                                    class="w-4 h-4 mr-1"
                                    fill="none"
                                    stroke="currentColor"
                                    viewBox="0 0 24 24"
                                  >
                                    <path
                                      stroke-linecap="round"
                                      stroke-linejoin="round"
                                      stroke-width="2"
                                      d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                                    />
                                  </svg>
                                  Primary Account
                                </span>
                              <% end %>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
              
    <!-- Add New Google Account -->
              <div class="relative group">
                <div class="absolute -inset-0.5 bg-gradient-to-r from-blue-600 to-green-600 rounded-xl blur opacity-20 group-hover:opacity-40 transition duration-1000 group-hover:duration-200">
                </div>
                <div class="relative bg-white rounded-xl shadow-lg border border-gray-100 overflow-hidden">
                  <div class="bg-gradient-to-r from-blue-500 to-green-500 px-8 py-6">
                    <div class="flex items-center space-x-3">
                      <div class="h-12 w-12 bg-white/20 rounded-xl flex items-center justify-center">
                        <svg
                          class="h-7 w-7 text-white"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M12 6v6m0 0v6m0-6h6m-6 0H6"
                          />
                        </svg>
                      </div>
                      <div>
                        <p class="text-blue-100">Add another Google account to sync more calendars</p>
                      </div>
                    </div>
                  </div>

                  <div class="p-8">
                    <div class="text-center">
                      <div class="mb-6">
                        <div class="inline-flex items-center justify-center w-12 h-12 bg-gradient-to-br from-blue-500 to-green-500 rounded-xl shadow-lg mb-4">
                          <svg class="w-6 h-6 text-white" fill="currentColor" viewBox="0 0 24 24">
                            <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                            <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                            <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
                            <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
                          </svg>
                        </div>
                        <h4 class="text-lg font-bold text-gray-900 mb-2">Connect Google Calendar</h4>
                        <p class="text-gray-600 max-w-md mx-auto">
                          Connect multiple Google accounts to sync events from different calendars. Each account can have its own meeting automation settings.
                        </p>
                      </div>

                      <div class="space-y-4 mb-8">
                        <div class="flex items-center justify-center space-x-2 text-sm text-gray-600">
                          <span>Automatic calendar event sync</span>
                        </div>
                        <div class="flex items-center justify-center space-x-2 text-sm text-gray-600">
                          <span>AI meeting transcription</span>
                        </div>
                        <div class="flex items-center justify-center space-x-2 text-sm text-gray-600">
                          <span>Automated content generation</span>
                        </div>
                      </div>

                      <button
                        phx-click="connect_google"
                        class="inline-flex items-center justify-center px-6 py-3 border border-transparent text-sm font-medium rounded-lg text-grey bg-gradient-to-r from-blue-500 to-green-500 hover:from-blue-600 hover:to-green-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 shadow-md transition-all duration-200 hover:shadow-lg"
                      >
                        <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 24 24">
                          <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                          <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                          <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
                          <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
                        </svg>
                        Connect Google Account
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </div>
        <% end %>
      </div>
    </div>
    """
  end
end
