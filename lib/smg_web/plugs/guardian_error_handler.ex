defmodule SMGWeb.GuardianErrorHandler do
  @moduledoc """
  Guardian error handler for authentication failures
  """
  import Plug.Conn
  import Phoenix.Controller

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, reason}, _opts) do
    require Logger
    Logger.debug("Guardian auth error: #{inspect(type)} - #{inspect(reason)} on path: #{conn.request_path}")

    # Check if this is a protected route that requires authentication
    requires_auth = conn.private[:phoenix_live_view] ||
                   String.contains?(conn.request_path, "/dashboard") ||
                   String.contains?(conn.request_path, "/meetings") ||
                   String.contains?(conn.request_path, "/posts") ||
                   String.contains?(conn.request_path, "/settings")

    # Clear session and set current_user to nil for auth errors
    conn = conn
           |> clear_session()
           |> assign(:current_user, nil)

    # If this is a protected route and we have auth errors, redirect to home
    if requires_auth do
      Logger.debug("Redirecting protected route due to auth error")
      conn
      |> put_flash(:error, "Your session has expired. Please log in again.")
      |> redirect(to: "/")
      |> halt()
    else
      # For non-protected routes, just continue with nil user
      Logger.debug("Continuing with nil user for non-protected route")
      conn
    end
  end
end
