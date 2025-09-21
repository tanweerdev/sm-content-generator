defmodule SMGWeb.AuthPlug do
  import Plug.Conn
  import Phoenix.Controller

  alias SMG.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)

    cond do
      current_user = user_id && Accounts.get_user(user_id) ->
        conn
        |> assign(:current_user, current_user)

      true ->
        conn
        |> assign(:current_user, nil)
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
