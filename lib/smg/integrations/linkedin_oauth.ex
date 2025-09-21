defmodule SMG.Integrations.LinkedInOAuth do
  @moduledoc """
  LinkedIn OAuth 2.0 implementation for connecting user accounts
  """

  use Tesla

  @oauth_base_url "https://www.linkedin.com/oauth/v2"
  @api_base_url "https://api.linkedin.com/v2"
  @token_url "https://www.linkedin.com/oauth/v2/accessToken"

  def authorization_url(redirect_uri, state \\ nil) do
    client_id = System.get_env("LINKEDIN_CLIENT_ID")
    scope = "openid profile email w_member_social"
    state = state || generate_state()

    query_params = %{
      response_type: "code",
      client_id: client_id,
      redirect_uri: redirect_uri,
      scope: scope,
      state: state
    }

    "#{@oauth_base_url}/authorization?" <> URI.encode_query(query_params)
  end

  def exchange_code_for_token(code, redirect_uri) do
    client_id = System.get_env("LINKEDIN_CLIENT_ID")
    client_secret = System.get_env("LINKEDIN_CLIENT_SECRET")

    require Logger

    Logger.info("Exchanging LinkedIn code for token",
      client_id: client_id,
      redirect_uri: redirect_uri
    )

    # Prepare form data as a map
    form_data = %{
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => redirect_uri,
      "client_id" => client_id,
      "client_secret" => client_secret
    }

    # Convert to URL-encoded string
    request_body = URI.encode_query(form_data)

    # Verify the encoding is correct
    Logger.info("Form data encoding verification",
      original_map: form_data,
      encoded_string: request_body,
      decoded_back: URI.decode_query(request_body)
    )

    Logger.info("LinkedIn token request details",
      url: @token_url,
      form_data: form_data,
      client_id: client_id
    )

    # Try Tesla's built-in form data handling
    client =
      Tesla.client([
        Tesla.Middleware.FormUrlencoded
      ])

    Logger.info("Making LinkedIn token request with Tesla FormUrlencoded",
      url: @token_url,
      form_data: form_data
    )

    # Use Tesla's form data handling - pass the map directly
    case Tesla.post(client, @token_url, form_data, headers: [{"Accept", "application/json"}]) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        Logger.info("LinkedIn token response success", body: response_body)

        case Jason.decode(response_body) do
          {:ok, token_data} ->
            {:ok, token_data}

          {:error, decode_error} ->
            Logger.error("Failed to decode LinkedIn token response",
              error: decode_error,
              body: response_body
            )

            {:error, "Failed to parse token response"}
        end

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        Logger.error("LinkedIn token exchange failed", status: status, body: error_body)

        # Handle both string and map responses
        error_message =
          case error_body do
            body when is_binary(body) ->
              case Jason.decode(body) do
                {:ok, %{"error_description" => desc}} -> desc
                {:ok, %{"error" => error}} -> error
                _ -> body
              end

            %{"error_description" => desc} ->
              desc

            %{"error" => error} ->
              error

            _ ->
              inspect(error_body)
          end

        {:error, "Token exchange failed with status #{status}: #{error_message}"}

      {:error, reason} ->
        Logger.error("LinkedIn token exchange network error", reason: inspect(reason))
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  def get_user_profile(access_token) do
    require Logger
    Logger.info("Getting LinkedIn user profile", access_token_length: String.length(access_token))

    # Use the v2 userinfo endpoint which is simpler and more reliable
    profile_url = "#{@api_base_url}/userinfo"

    # Use a client with JSON middleware for API calls
    client =
      Tesla.client([
        Tesla.Middleware.JSON,
        {Tesla.Middleware.Timeout, timeout: 30_000}
      ])

    headers = [{"Authorization", "Bearer #{access_token}"}]

    Logger.info("Making LinkedIn profile request",
      url: profile_url,
      headers: headers
    )

    case Tesla.get(client, profile_url, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: profile_data}} when is_map(profile_data) ->
        Logger.info("LinkedIn profile response (map)", data: profile_data)
        {:ok, format_user_data(profile_data)}

      {:ok, %Tesla.Env{status: 200, body: response_body}} when is_binary(response_body) ->
        Logger.info("LinkedIn profile response (string)", body: response_body)

        case Jason.decode(response_body) do
          {:ok, profile_data} ->
            {:ok, format_user_data(profile_data)}

          {:error, decode_error} ->
            Logger.error("Failed to parse LinkedIn profile response",
              error: decode_error,
              body: response_body
            )

            {:error, "Failed to parse profile response"}
        end

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("LinkedIn profile fetch failed", status: status, body: body)
        {:error, "Profile fetch failed with status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("LinkedIn profile network error", reason: inspect(reason))
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp format_user_data(profile_data) do
    require Logger
    Logger.info("Formatting LinkedIn user data", profile_data: profile_data)

    # Handle both old and new API response formats
    user_data = %{
      platform_user_id: profile_data["sub"] || profile_data["id"],
      email: profile_data["email"] || profile_data["emailAddress"],
      name: profile_data["name"] || build_name_from_parts(profile_data),
      avatar_url:
        profile_data["picture"] || extract_profile_picture(profile_data["profilePicture"])
    }

    Logger.info("Formatted LinkedIn user data", user_data: user_data)
    user_data
  end

  defp build_name_from_parts(profile_data) do
    first_name =
      get_in(profile_data, ["firstName", "localized", "en_US"]) ||
        get_in(profile_data, ["firstName", "preferredLocale", "en_US"]) ||
        profile_data["given_name"] ||
        ""

    last_name =
      get_in(profile_data, ["lastName", "localized", "en_US"]) ||
        get_in(profile_data, ["lastName", "preferredLocale", "en_US"]) ||
        profile_data["family_name"] ||
        ""

    "#{first_name} #{last_name}" |> String.trim()
  end

  defp extract_profile_picture(nil), do: nil

  defp extract_profile_picture(profile_picture) do
    get_in(profile_picture, [
      "displayImage~",
      "elements",
      Access.at(0),
      "identifiers",
      Access.at(0),
      "identifier"
    ])
  end

  defp generate_state do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
