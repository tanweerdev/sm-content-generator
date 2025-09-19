defmodule SMGWeb.PageController do
  use SMGWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: "/dashboard")
    else
      render(conn, :home)
    end
  end
end
