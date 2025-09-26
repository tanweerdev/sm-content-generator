defmodule SMGWeb.AuthController do
  use SMGWeb, :controller

  alias SMG.Accounts
  alias SMG.Auth.Guardian

  def request(conn, %{"provider" => provider})
      when provider in ["google", "facebook", "linkedin"] do
    case provider do
      "google" ->
        redirect_to_google(conn)

      "facebook" ->
        redirect_to_facebook(conn)

      "linkedin" ->
        redirect_to_linkedin(conn)
    end
  end

  def request(conn, _params) do
    conn
    |> put_flash(:error, "Authentication provider not specified")
    |> redirect(to: "/")
  end

  def callback(
        conn,
        %{"provider" => "linkedin"} = params
      ) do
    SMGWeb.LinkedInAuthController.callback(conn, params)
  end

  def callback(conn, %{"provider" => "google", "code" => code, "state" => state}) do
    if verify_state(conn, state) do
      handle_google_callback(conn, code)
    else
      conn
      |> put_flash(:error, "Invalid authentication state. Please try again.")
      |> redirect(to: "/")
    end
  end

  def callback(conn, %{"provider" => "facebook", "code" => code, "state" => state}) do
    if verify_state(conn, state) do
      handle_facebook_callback(conn, code)
    else
      conn
      |> put_flash(:error, "Invalid authentication state. Please try again.")
      |> redirect(to: "/")
    end
  end

  def callback(conn, %{"provider" => "linkedin", "code" => code, "state" => state}) do
    if verify_state(conn, state) do
      handle_linkedin_callback(conn, code)
    else
      conn
      |> put_flash(:error, "Invalid authentication state. Please try again.")
      |> redirect(to: "/")
    end
  end

  def callback(conn, %{"provider" => provider, "error" => error}) do
    require Logger
    Logger.warning("OAuth callback error", provider: provider, error: error)

    conn
    |> put_flash(:error, "Authentication was cancelled or failed.")
    |> redirect(to: "/")
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed.")
    |> redirect(to: "/")
  end

  def logout(conn, _params) do
    require Logger

    Logger.info("User logging out", user_id: get_session(conn, :user_id))

    # Sign out from Guardian and revoke token
    conn
    |> Guardian.Plug.sign_out()
    |> clear_session()
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: "/")
  end

  def clear_session(conn, _params) do
    # Clear all session data to fix stale session issues
    conn
    |> Guardian.Plug.sign_out()
    |> clear_session()
    |> put_flash(:info, "Session cleared. Please try logging in again.")
    |> redirect(to: "/")
  end

  defp handle_google_auth(conn, auth) do
    require Logger
    current_user = get_current_user(conn)

    Logger.info("Google auth callback",
      current_user_id: current_user && current_user.id,
      google_email: auth.info.email,
      is_additional_account: !!current_user
    )

    if current_user do
      # User is already logged in, add this as an additional Google account
      Logger.info("Adding additional Google account for user",
        user_id: current_user.id,
        email: auth.info.email
      )

      case connect_google_account(current_user, auth) do
        {:ok, google_account} ->
          Logger.info("Successfully connected additional Google account",
            user_id: current_user.id,
            google_account_id: google_account.id,
            email: google_account.email
          )

          conn
          |> put_flash(
            :info,
            "Successfully connected additional Google account: #{auth.info.email}"
          )
          |> redirect(to: "/settings?tab=google")

        {:error, reason} ->
          Logger.error("Failed to connect additional Google account",
            user_id: current_user.id,
            email: auth.info.email,
            reason: inspect(reason)
          )

          conn
          |> put_flash(:error, "Failed to connect Google account: #{reason}")
          |> redirect(to: "/settings?tab=google")
      end
    else
      # User is not logged in, handle as initial login
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

          # Use Guardian to sign in the user with JWT token
          case Guardian.authenticate(user) do
            {:ok, %{token: token}} ->
              conn
              |> Guardian.Plug.sign_in(user)
              # Keep session as backup
              |> put_session(:user_id, user.id)
              |> put_resp_header("authorization", "Bearer " <> token)
              |> put_flash(
                :info,
                "Successfully authenticated with Google. Syncing your calendar..."
              )
              |> redirect(to: "/dashboard")

            {:error, reason} ->
              IO.inspect(reason, label: "reasonreasonreasonreasonreasonreasonreasonreason")

              conn
              |> put_flash(:error, "Authentication token generation failed")
              |> redirect(to: "/")
          end

        {:error, reason} ->
          conn
          |> put_flash(:error, "Google authentication failed: #{reason}")
          |> redirect(to: "/")
      end
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
      expires_at: auth.credentials.expires_at,
      scope: Enum.join(auth.credentials.scopes || [], " ")
    }

    case Accounts.upsert_user_with_google_account(user_params, google_account_params) do
      {:ok, user} -> {:ok, user}
      {:error, _changeset} -> {:error, "Invalid user data"}
    end
  end

  defp connect_google_account(user, auth) do
    google_account_params = %{
      google_user_id: auth.uid,
      email: auth.info.email,
      access_token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      expires_at: auth.credentials.expires_at,
      scope: Enum.join(auth.credentials.scopes || [], " "),
      user_id: user.id
    }

    Accounts.create_or_update_google_account(google_account_params)
  end

  defp get_current_user(conn) do
    conn.assigns[:current_user]
  end

  # Custom OAuth redirect functions
  defp redirect_to_google(conn) do
    client_id = System.get_env("GOOGLE_CLIENT_ID")
    redirect_uri = get_redirect_uri(conn, "google")

    state = generate_state()

    google_auth_url =
      "https://accounts.google.com/o/oauth2/v2/auth?" <>
        "client_id=#{URI.encode(client_id)}" <>
        "&redirect_uri=#{URI.encode(redirect_uri)}" <>
        "&response_type=code" <>
        "&scope=#{URI.encode("openid email profile https://www.googleapis.com/auth/calendar.readonly")}" <>
        "&access_type=offline" <>
        "&prompt=consent select_account" <>
        "&state=#{state}"

    conn
    |> put_session(:oauth_state, state)
    |> redirect(external: google_auth_url)
  end

  defp redirect_to_facebook(conn) do
    client_id = System.get_env("FACEBOOK_APP_ID")
    redirect_uri = get_redirect_uri(conn, "facebook")

    state = generate_state()

    facebook_auth_url =
      "https://www.facebook.com/v18.0/dialog/oauth?" <>
        "client_id=#{URI.encode(client_id)}" <>
        "&redirect_uri=#{URI.encode(redirect_uri)}" <>
        "&response_type=code" <>
        "&scope=#{URI.encode("email,public_profile,publish_to_groups")}" <>
        "&state=#{state}"

    conn
    |> put_session(:oauth_state, state)
    |> redirect(external: facebook_auth_url)
  end

  defp redirect_to_linkedin(conn) do
    client_id = System.get_env("LINKEDIN_CLIENT_ID")
    redirect_uri = get_redirect_uri(conn, "linkedin")

    state = generate_state()

    linkedin_auth_url =
      "https://www.linkedin.com/oauth/v2/authorization?" <>
        "client_id=#{URI.encode(client_id)}" <>
        "&redirect_uri=#{URI.encode(redirect_uri)}" <>
        "&response_type=code" <>
        "&scope=#{URI.encode("openid profile email w_member_social")}" <>
        "&state=#{state}"

    conn
    |> put_session(:oauth_state, state)
    |> redirect(external: linkedin_auth_url)
  end

  defp get_redirect_uri(_conn, provider) do
    scheme = System.get_env("SCHEME") || "http"
    host = System.get_env("SERVER_HOST") || "localhost"
    port_env = System.get_env("URL_PORT") || "4000"

    port =
      case {scheme, port_env} do
        {"https", "443"} -> ""
        {"http", "80"} -> ""
        {_, port} -> ":#{port}"
      end

    "#{scheme}://#{host}#{port}/auth/#{provider}/callback"
  end

  defp generate_state do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp verify_state(conn, state) do
    stored_state = get_session(conn, :oauth_state)
    stored_state && stored_state == state
  end

  defp handle_google_callback(conn, code) do
    redirect_uri = get_redirect_uri(conn, "google")

    case exchange_google_code_for_token(code, redirect_uri) do
      {:ok, token_data} ->
        case get_google_user_info(token_data["access_token"]) do
          {:ok, user_info} ->
            # Create a fake auth struct similar to Ueberauth for compatibility
            auth = %{
              uid: user_info["id"],
              info: %{
                email: user_info["email"],
                name: user_info["name"],
                image: user_info["picture"]
              },
              credentials: %{
                token: token_data["access_token"],
                refresh_token: token_data["refresh_token"],
                expires_at: DateTime.add(DateTime.utc_now(), token_data["expires_in"] || 3600, :second),
                scopes: String.split(token_data["scope"] || "", " ")
              }
            }

            handle_google_auth(conn, auth)

          {:error, reason} ->
            conn
            |> put_flash(:error, "Failed to get user information: #{reason}")
            |> redirect(to: "/")
        end

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to exchange authorization code: #{reason}")
        |> redirect(to: "/")
    end
  end

  defp handle_facebook_callback(conn, _code) do
    # Implementation for Facebook OAuth callback
    conn
    |> put_flash(:error, "Facebook authentication not yet implemented")
    |> redirect(to: "/")
  end

  defp handle_linkedin_callback(conn, _code) do
    # Implementation for LinkedIn OAuth callback
    conn
    |> put_flash(:error, "LinkedIn authentication not yet implemented")
    |> redirect(to: "/")
  end

  defp exchange_google_code_for_token(code, redirect_uri) do
    client_id = System.get_env("GOOGLE_CLIENT_ID")
    client_secret = System.get_env("GOOGLE_CLIENT_SECRET")

    body = %{
      client_id: client_id,
      client_secret: client_secret,
      code: code,
      grant_type: "authorization_code",
      redirect_uri: redirect_uri
    }

    case HTTPoison.post("https://oauth2.googleapis.com/token", URI.encode_query(body), [
           {"Content-Type", "application/x-www-form-urlencoded"}
         ]) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: status, body: body}} ->
        {:error, "HTTP #{status}: #{body}"}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  defp get_google_user_info(access_token) do
    case HTTPoison.get("https://www.googleapis.com/oauth2/v2/userinfo", [
           {"Authorization", "Bearer #{access_token}"}
         ]) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: status, body: body}} ->
        {:error, "HTTP #{status}: #{body}"}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end
end
