defmodule SMGWeb.GuardianErrorHandler do
  @moduledoc """
  Guardian error handler for authentication failures
  """
  import Plug.Conn

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, _reason}, _opts) do
    case type do
      :invalid_token ->
        conn
        |> clear_session()
        |> assign(:current_user, nil)

      :token_expired ->
        conn
        |> clear_session()
        |> assign(:current_user, nil)

      :no_resource_found ->
        conn
        |> clear_session()
        |> assign(:current_user, nil)

      _ ->
        conn
        |> assign(:current_user, nil)
    end
  end
end
