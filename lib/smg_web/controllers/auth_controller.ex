defmodule SMGWeb.AuthController do
  use SMGWeb, :controller
  plug Ueberauth

  alias SMG.Accounts

  def request(conn, _params) do
    # Redirects to OAuth provider
    redirect(conn, external: "/auth/google")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case upsert_user_from_auth(auth) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Successfully authenticated.")
        |> redirect(to: "/dashboard")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Authentication failed: #{reason}")
        |> redirect(to: "/")
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed.")
    |> redirect(to: "/")
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: "/")
  end

  defp upsert_user_from_auth(auth) do
    user_params = %{
      email: auth.info.email,
      name: auth.info.name,
      avatar_url: auth.info.image
    }

    google_account_params = %{
      google_user_id: auth.uid,
      email: auth.info.email,
      access_token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      expires_at: auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at),
      scope: Enum.join(auth.credentials.scopes || [], " ")
    }

    case Accounts.upsert_user_with_google_account(user_params, google_account_params) do
      {:ok, user} -> {:ok, user}
      {:error, changeset} -> {:error, "Invalid user data"}
    end
  end
end