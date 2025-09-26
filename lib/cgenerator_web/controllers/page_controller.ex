defmodule SMGWeb.PageController do
  use SMGWeb, :controller

  def home(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        render(conn, :home)

      _user ->
        redirect(conn, to: "/dashboard")
    end
  end
end
