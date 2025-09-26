defmodule SMGWeb.GuardianAuthPlug do
  @moduledoc """
  Guardian-based authentication plug that provides secure session management.
  Prevents user session conflicts by using JWT tokens instead of shared sessions.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias SMG.Auth.Guardian

  def init(opts), do: opts

  def call(conn, _opts) do
    require Logger
    Logger.debug("GuardianAuthPlug called for path: #{conn.request_path}")

    # Only run this logic if current_user hasn't already been set
    if conn.assigns[:current_user] do
      Logger.debug("Current user already set, skipping")
      conn
    else
      try do
        # Check if Guardian plugs have run (they set this private key)
        guardian_ran = conn.private[:guardian_default_resource] != nil

        if guardian_ran do
          # Guardian plugs have run, get the user from Guardian
          current_user = Guardian.Plug.current_resource(conn)
          Logger.debug("Current user from Guardian: #{inspect(current_user != nil)}")

          conn
          |> assign(:current_user, current_user)
        else
          # Guardian plugs haven't run (non-protected route), check session
          user_id = get_session(conn, :user_id)
          Logger.debug("Checking session for user_id: #{inspect(user_id)}")

          if user_id do
            case SMG.Accounts.get_user(user_id) do
              nil ->
                Logger.debug("User not found in database, clearing session")
                conn
                |> assign(:current_user, nil)
                |> clear_session()

              user ->
                Logger.debug("Found user in session: #{user.id}")
                conn
                |> assign(:current_user, user)
            end
          else
            Logger.debug("No user_id in session")
            conn
            |> assign(:current_user, nil)
          end
        end
      rescue
        error ->
          # If anything fails, clear session and continue
          Logger.error("Error in GuardianAuthPlug: #{inspect(error)}")
          conn
          |> assign(:current_user, nil)
          |> clear_session()
      end
    end
  end

  def require_auth(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in to access this page")
      |> redirect(to: "/")
      |> halt()
    end
  end
end
