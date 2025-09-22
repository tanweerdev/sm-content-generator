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
    # Try to get user from Guardian first (from token)
    current_user = Guardian.Plug.current_resource(conn)

    if current_user do
      conn
      |> assign(:current_user, current_user)
    else
      # Try to get user from session as fallback for existing sessions
      user_id = get_session(conn, :user_id)

      if user_id do
        case SMG.Accounts.get_user(user_id) do
          nil ->
            conn
            |> assign(:current_user, nil)
            |> clear_session()

          user ->
            # Create a new Guardian token for the user
            case Guardian.authenticate(user) do
              {:ok, %{token: _token}} ->
                conn
                |> Guardian.Plug.sign_in(user)
                |> assign(:current_user, user)

              {:error, _reason} ->
                conn
                |> assign(:current_user, nil)
                |> clear_session()
            end
        end
      else
        conn
        |> assign(:current_user, nil)
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
