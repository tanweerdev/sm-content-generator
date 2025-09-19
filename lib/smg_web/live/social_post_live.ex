defmodule SMGWeb.SocialPostLive do
  use SMGWeb, :live_view

  alias SMG.{Social, Services.SocialMediaPoster}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    social_post = Social.get_social_post_for_user!(id, user)

    socket =
      socket
      |> assign(:social_post, social_post)
      |> assign(:user, user)
      |> assign(:editing, false)
      |> assign(:posting, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, assign(socket, :editing, true)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  @impl true
  def handle_event("save", %{"content" => content}, socket) do
    social_post = socket.assigns.social_post

    case Social.update_social_post(social_post, %{content: content}) do
      {:ok, updated_post} ->
        socket =
          socket
          |> assign(:social_post, updated_post)
          |> assign(:editing, false)
          |> put_flash(:info, "Post updated successfully!")

        {:noreply, socket}

      {:error, _changeset} ->
        socket =
          socket
          |> put_flash(:error, "Failed to update post")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("post_to_social", _params, socket) do
    social_post = socket.assigns.social_post

    if social_post.status == "draft" do
      socket = assign(socket, :posting, true)

      # Post in the background
      Task.start(fn ->
        case SocialMediaPoster.post_to_platform(social_post) do
          {:ok, _updated_post} ->
            send(self(), {:post_success, "Post published successfully!"})

          {:error, reason} ->
            send(self(), {:post_error, reason})
        end
      end)

      {:noreply, socket}
    else
      socket =
        socket
        |> put_flash(:error, "This post has already been published")

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_post", _params, socket) do
    social_post = socket.assigns.social_post

    case Social.delete_social_post(social_post) do
      {:ok, _} ->
        {:noreply, redirect(socket, to: "/dashboard")}

      {:error, _} ->
        socket =
          socket
          |> put_flash(:error, "Failed to delete post")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:post_success, message}, socket) do
    # Reload the post to get updated status
    social_post = Social.get_social_post_for_user!(socket.assigns.social_post.id, socket.assigns.user)

    socket =
      socket
      |> assign(:social_post, social_post)
      |> assign(:posting, false)
      |> put_flash(:info, message)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:post_error, reason}, socket) do
    socket =
      socket
      |> assign(:posting, false)
      |> put_flash(:error, "Failed to publish post: #{reason}")

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8">
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
                  <svg class="flex-shrink-0 h-5 w-5 text-gray-300" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                    <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z" clip-rule="evenodd" />
                  </svg>
                  <span class="ml-4 text-sm font-medium text-gray-500">Social Post</span>
                </div>
              </li>
            </ol>
          </nav>

          <div class="mt-4 flex items-center justify-between">
            <h1 class="text-3xl font-bold text-gray-900">
              Social Media Post
            </h1>
            <div class="flex items-center space-x-3">
              <span class={"inline-flex items-center px-3 py-1 rounded-full text-sm font-medium #{status_color(@social_post.status)}"}>
                <%= String.capitalize(@social_post.status) %>
              </span>
              <span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-blue-100 text-blue-800">
                <%= String.capitalize(@social_post.platform) %>
              </span>
              <a href="/auth/logout" class="inline-flex items-center px-3 py-1 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">
                Logout
              </a>
            </div>
          </div>
        </div>

        <!-- Main Content -->
        <div class="bg-white shadow rounded-lg">
          <div class="px-6 py-6">
            <%= if @editing do %>
              <!-- Edit Mode -->
              <form phx-submit="save">
                <div class="mb-4">
                  <label for="content" class="block text-sm font-medium text-gray-700 mb-2">
                    Post Content
                  </label>
                  <textarea
                    id="content"
                    name="content"
                    rows="8"
                    class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    placeholder="Write your social media post..."
                  ><%= @social_post.content %></textarea>
                </div>
                <div class="flex items-center justify-end space-x-3">
                  <button
                    type="button"
                    phx-click="cancel_edit"
                    class="bg-white py-2 px-4 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="bg-indigo-600 py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                  >
                    Save Changes
                  </button>
                </div>
              </form>
            <% else %>
              <!-- View Mode -->
              <div class="mb-6">
                <h3 class="text-lg font-medium text-gray-900 mb-3">Content</h3>
                <div class="bg-gray-50 rounded-lg p-4">
                  <p class="text-gray-900 whitespace-pre-wrap"><%= @social_post.content %></p>
                </div>
              </div>

              <%= if @social_post.calendar_event do %>
                <div class="mb-6">
                  <h3 class="text-lg font-medium text-gray-900 mb-3">Generated From</h3>
                  <div class="bg-blue-50 rounded-lg p-4">
                    <div class="flex items-center">
                      <svg class="h-5 w-5 text-blue-400 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                      </svg>
                      <span class="text-blue-900 font-medium">
                        <%= @social_post.calendar_event.title || "Meeting" %>
                      </span>
                    </div>
                    <%= if @social_post.calendar_event.start_time do %>
                      <p class="text-blue-700 text-sm mt-1">
                        <%= format_datetime(@social_post.calendar_event.start_time) %>
                      </p>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <!-- Actions -->
              <div class="flex items-center justify-between pt-6 border-t border-gray-200">
                <div class="flex items-center space-x-3">
                  <%= if @social_post.status == "draft" do %>
                    <button
                      phx-click="edit"
                      class="bg-white py-2 px-4 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                    >
                      Edit Content
                    </button>
                    <button
                      phx-click="post_to_social"
                      disabled={@posting}
                      class={"bg-indigo-600 py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 #{if @posting, do: "opacity-50 cursor-not-allowed"}"}
                    >
                      <%= if @posting do %>
                        <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white inline" fill="none" viewBox="0 0 24 24">
                          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                        </svg>
                        Publishing...
                      <% else %>
                        Publish to <%= String.capitalize(@social_post.platform) %>
                      <% end %>
                    </button>
                  <% end %>
                </div>

                <button
                  phx-click="delete_post"
                  data-confirm="Are you sure you want to delete this post?"
                  class="text-red-600 hover:text-red-500 text-sm font-medium"
                >
                  Delete Post
                </button>
              </div>

              <%= if @social_post.status == "posted" do %>
                <div class="mt-4 bg-green-50 rounded-lg p-4">
                  <div class="flex">
                    <svg class="h-5 w-5 text-green-400" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                    </svg>
                    <div class="ml-3">
                      <p class="text-sm font-medium text-green-800">
                        Successfully posted to <%= String.capitalize(@social_post.platform) %>
                      </p>
                      <%= if @social_post.posted_at do %>
                        <p class="text-sm text-green-700 mt-1">
                          Posted on <%= format_datetime(@social_post.posted_at) %>
                        </p>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_color("draft"), do: "bg-yellow-100 text-yellow-800"
  defp status_color("posted"), do: "bg-green-100 text-green-800"
  defp status_color("failed"), do: "bg-red-100 text-red-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp format_datetime(nil), do: "Unknown"

  defp format_datetime(datetime) do
    datetime
    |> Calendar.strftime("%B %d, %Y at %I:%M %p")
  end
end
