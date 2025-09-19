defmodule SMGWeb.PageController do
  use SMGWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
