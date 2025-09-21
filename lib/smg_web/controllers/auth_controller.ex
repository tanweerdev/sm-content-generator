defmodule SMGWeb.AuthController do
  use SMGWeb, :controller
  plug Ueberauth

  alias SMG.Accounts

  def request(conn, _params) do
    # Let Ueberauth handle the redirect
    # This will be handled by the Ueberauth plug
    conn
  end

  def callback(
        conn,
        %{"provider" => "linkedin"} = params
      ) do
    SMGWeb.LinkedInAuthController.callback(conn, params)
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => provider}) do
    require Logger

    Logger.info("OAuth callback received",
      provider: provider,
      uid: auth.uid,
      email: auth.info.email,
      scopes: auth.credentials.scopes,
      token_length: String.length(auth.credentials.token)
    )

    case provider do
      "google" ->
        handle_google_auth(conn, auth)

      provider when provider in ["facebook"] ->
        handle_social_platform_auth(conn, auth, provider)

      _ ->
        conn
        |> put_flash(:error, "Unsupported authentication provider.")
        |> redirect(to: "/")
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed.")
    |> redirect(to: "/")
  end

  def logout(conn, _params) do
    require Logger

    Logger.info("User logging out", user_id: get_session(conn, :user_id))

    conn
    |> clear_session()
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: "/")
  end

  defp handle_google_auth(conn, auth) do
    case upsert_user_from_google_auth(auth) do
      {:ok, user} ->
        # Trigger automatic calendar sync after successful login
        case SMG.Accounts.list_user_google_accounts(user) do
          [google_account | _] ->
            Task.start(fn ->
              SMG.Integrations.GoogleCalendar.sync_events(google_account)
            end)

          [] ->
            :ok
        end

        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Successfully authenticated with Google. Syncing your calendar...")
        |> redirect(to: "/dashboard")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Google authentication failed: #{reason}")
        |> redirect(to: "/")
    end
  end

  defp handle_social_platform_auth(conn, auth, platform) do
    current_user = get_current_user(conn)

    if current_user do
      case connect_social_platform(current_user, auth, platform) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "Successfully connected #{String.capitalize(platform)} account!")
          |> redirect(to: "/settings")

        {:error, reason} ->
          conn
          |> put_flash(:error, "Failed to connect #{platform}: #{reason}")
          |> redirect(to: "/settings")
      end
    else
      conn
      |> put_flash(:error, "Please log in first before connecting social accounts.")
      |> redirect(to: "/")
    end
  end

  defp upsert_user_from_google_auth(auth) do
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
      {:error, _changeset} -> {:error, "Invalid user data"}
    end
  end

  defp connect_social_platform(user, auth, platform) do
    platform_data = %{
      platform_user_id: auth.uid,
      email: auth.info.email || auth.info.nickname,
      access_token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      expires_at: auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at),
      scope: Enum.join(auth.credentials.scopes || [], " ")
    }

    SMG.Settings.connect_social_platform(user, platform, platform_data)
  end

  defp get_current_user(conn) do
    user_id = get_session(conn, :user_id)
    user_id && Accounts.get_user(user_id)
  end
end
