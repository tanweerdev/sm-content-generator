defmodule SMGWeb.LinkedInAuthController do
  use SMGWeb, :controller

  alias SMG.Integrations.LinkedInOAuth
  alias SMG.{Accounts, Settings}

  require Logger

  def authorize(conn, _params) do
    # Check if LinkedIn credentials are configured
    client_id = System.get_env("LINKEDIN_CLIENT_ID")
    client_secret = System.get_env("LINKEDIN_CLIENT_SECRET")

    Logger.info("LinkedIn auth attempt",
      client_id_present: !is_nil(client_id) && client_id != "",
      client_secret_present: !is_nil(client_secret) && client_secret != ""
    )

    if is_nil(client_id) || client_id == "" || is_nil(client_secret) || client_secret == "" do
      Logger.error("LinkedIn OAuth credentials not configured")

      conn
      |> put_flash(
        :error,
        "LinkedIn integration is not configured. Please contact the administrator."
      )
      |> redirect(to: "/settings")
    else
      try do
        # Generate state for CSRF protection
        state = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
        conn = put_session(conn, :linkedin_oauth_state, state)

        redirect_uri = get_redirect_uri(conn)

        # Pass state to authorization URL
        auth_url = LinkedInOAuth.authorization_url(redirect_uri, state)

        Logger.info("Redirecting to LinkedIn OAuth",
          url: auth_url,
          state: state,
          redirect_uri: redirect_uri
        )

        redirect(conn, external: auth_url)
      rescue
        e ->
          Logger.error("Error generating LinkedIn auth URL", error: inspect(e))

          conn
          |> put_flash(:error, "Failed to initiate LinkedIn connection")
          |> redirect(to: "/settings")
      end
    end
  end

  def callback(conn, %{"code" => code, "state" => state} = params) do
    Logger.info("LinkedIn OAuth callback received", params: params)

    # Verify state for CSRF protection
    session_state = get_session(conn, :linkedin_oauth_state)

    if state != session_state do
      Logger.error("LinkedIn OAuth state mismatch",
        received: state,
        expected: session_state
      )

      conn
      |> put_flash(:error, "Invalid OAuth state. Please try connecting LinkedIn again.")
      |> redirect(to: "/settings")
    else
      # Clear state from session
      conn = delete_session(conn, :linkedin_oauth_state)

      handle_oauth_success(conn, code)
    end
  end

  def callback(conn, %{"error" => error, "error_description" => error_description}) do
    Logger.error("LinkedIn OAuth error", error: error, description: error_description)

    conn
    |> put_flash(:error, "LinkedIn authorization failed: #{error_description}")
    |> redirect(to: "/settings")
  end

  def callback(conn, _params) do
    Logger.error("LinkedIn OAuth callback with missing parameters")

    conn
    |> put_flash(:error, "LinkedIn authorization failed: missing required parameters")
    |> redirect(to: "/settings")
  end

  defp handle_oauth_success(conn, code) do
    current_user = get_current_user(conn)

    if current_user do
      redirect_uri = get_redirect_uri(conn)

      case LinkedInOAuth.exchange_code_for_token(code, redirect_uri) do
        {:ok, token_data} ->
          handle_token_success(conn, current_user, token_data)

        {:error, reason} ->
          Logger.error("LinkedIn token exchange failed", reason: reason)

          conn
          |> put_flash(:error, "Failed to connect LinkedIn: #{reason}")
          |> redirect(to: "/settings")
      end
    else
      conn
      |> put_flash(:error, "Please log in first before connecting social accounts.")
      |> redirect(to: "/")
    end
  end

  defp handle_token_success(conn, user, token_data) do
    case LinkedInOAuth.get_user_profile(token_data["access_token"]) do
      {:ok, profile_data} ->
        platform_data = %{
          platform_user_id: profile_data.platform_user_id,
          email: profile_data.email,
          access_token: token_data["access_token"],
          refresh_token: token_data["refresh_token"],
          expires_at: calculate_expires_at(token_data["expires_in"]),
          scope: token_data["scope"] || "profile email w_member_social"
        }

        case Settings.connect_social_platform(user, "linkedin", platform_data) do
          {:ok, _connection} ->
            Logger.info("LinkedIn account connected successfully", user_id: user.id)

            conn
            |> put_flash(:info, "Successfully connected LinkedIn account!")
            |> redirect(to: "/settings")

          {:error, reason} ->
            Logger.error("Failed to save LinkedIn connection", reason: reason)

            conn
            |> put_flash(:error, "Failed to save LinkedIn connection: #{inspect(reason)}")
            |> redirect(to: "/settings")
        end

      {:error, reason} ->
        Logger.error("Failed to get LinkedIn profile", reason: reason)

        conn
        |> put_flash(:error, "Failed to get LinkedIn profile: #{reason}")
        |> redirect(to: "/settings")
    end
  end

  defp get_current_user(conn) do
    user_id = get_session(conn, :user_id)
    user_id && Accounts.get_user(user_id)
  end

  defp get_redirect_uri(conn) do
    # Build the callback URL based on current request
    scheme = if conn.scheme == :https, do: "https", else: "http"
    host = get_req_header(conn, "host") |> List.first() || "localhost:4001"
    "#{scheme}://#{host}/auth/linkedin/callback"
    "https://jump.mynotifire.com/auth/linkedin/callback"
  end

  defp calculate_expires_at(nil), do: nil

  defp calculate_expires_at(expires_in) when is_integer(expires_in) do
    DateTime.utc_now() |> DateTime.add(expires_in, :second)
  end

  defp calculate_expires_at(expires_in) when is_binary(expires_in) do
    case Integer.parse(expires_in) do
      {seconds, _} -> calculate_expires_at(seconds)
      :error -> nil
    end
  end
end
