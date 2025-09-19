defmodule SMGWeb.AuthOnMount do
  @moduledoc """
  LiveView on_mount callbacks for authentication.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  alias SMG.Accounts

  def on_mount(:ensure_authenticated, _params, session, socket) do
    user_id = session["user_id"]

    cond do
      current_user = user_id && Accounts.get_user(user_id) ->
        {:cont, assign(socket, :current_user, current_user)}

      true ->
        socket =
          socket
          |> put_flash(:error, "You must be logged in to access this page")
          |> redirect(to: "/")

        {:halt, socket}
    end
  end

  def on_mount(:assign_current_user, _params, session, socket) do
    user_id = session["user_id"]

    current_user = if user_id, do: Accounts.get_user(user_id), else: nil

    {:cont, assign(socket, :current_user, current_user)}
  end
end
