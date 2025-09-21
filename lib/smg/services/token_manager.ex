defmodule SMG.Services.TokenManager do
  @moduledoc """
  Utility functions for managing OAuth tokens across all platforms.
  Provides convenience functions for checking token status, forcing refreshes,
  and monitoring token health.
  """

  import Ecto.Query
  require Logger

  alias SMG.Repo
  alias SMG.Accounts.GoogleAccount
  alias SMG.Settings.SocialConnection
  alias SMG.Services.OAuthTokenRefresher

  @doc """
  Gets the status of all OAuth tokens for a user
  """
  def get_token_status(user) do
    google_accounts = get_user_google_accounts(user)
    social_connections = get_user_social_connections(user)

    %{
      google: Enum.map(google_accounts, &format_google_token_status/1),
      social: Enum.map(social_connections, &format_social_token_status/1)
    }
  end

  @doc """
  Gets all tokens that are expiring soon (within the next hour)
  """
  def get_expiring_tokens do
    buffer_time = DateTime.add(DateTime.utc_now(), :timer.hours(1), :millisecond)

    google_accounts =
      from(ga in GoogleAccount,
        where: not is_nil(ga.expires_at) and ga.expires_at <= ^buffer_time,
        preload: [:user]
      )
      |> Repo.all()

    social_connections =
      from(sc in SocialConnection,
        where: not is_nil(sc.expires_at) and sc.expires_at <= ^buffer_time,
        preload: [:user]
      )
      |> Repo.all()

    %{
      google: google_accounts,
      social: social_connections,
      total_count: length(google_accounts) + length(social_connections)
    }
  end

  @doc """
  Forces an immediate refresh of all expiring tokens
  """
  def force_refresh_all do
    case OAuthTokenRefresher.force_refresh() do
      {:ok, count} ->
        Logger.info("Force refresh completed", refreshed_tokens: count)
        {:ok, count}

      {:error, reason} ->
        Logger.error("Force refresh failed", reason: reason)
        {:error, reason}
    end
  end

  @doc """
  Checks if a specific token needs refresh
  """
  def needs_refresh?(%GoogleAccount{expires_at: nil}), do: false
  def needs_refresh?(%SocialConnection{expires_at: nil}), do: false

  def needs_refresh?(%GoogleAccount{expires_at: expires_at}) do
    check_expiry(expires_at)
  end

  def needs_refresh?(%SocialConnection{expires_at: expires_at}) do
    check_expiry(expires_at)
  end

  @doc """
  Gets token health report for all platforms
  """
  def get_health_report do
    google_accounts = Repo.all(GoogleAccount)
    social_connections = Repo.all(SocialConnection)

    google_stats = analyze_tokens(google_accounts, &extract_google_expiry/1)
    social_stats = analyze_tokens(social_connections, &extract_social_expiry/1)

    %{
      google: google_stats,
      social: social_stats,
      total_accounts: length(google_accounts) + length(social_connections),
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Validates that all required environment variables are set
  """
  def validate_environment do
    required_vars = [
      {"GOOGLE_CLIENT_ID", "Google OAuth"},
      {"GOOGLE_CLIENT_SECRET", "Google OAuth"},
      {"FACEBOOK_APP_ID", "Facebook OAuth"},
      {"FACEBOOK_APP_SECRET", "Facebook OAuth"},
      {"LINKEDIN_CLIENT_ID", "LinkedIn OAuth"},
      {"LINKEDIN_CLIENT_SECRET", "LinkedIn OAuth"}
    ]

    missing_vars =
      Enum.filter(required_vars, fn {var, _desc} ->
        System.get_env(var) == nil
      end)

    if Enum.empty?(missing_vars) do
      {:ok, "All OAuth environment variables are configured"}
    else
      missing_descriptions = Enum.map(missing_vars, fn {_var, desc} -> desc end)
      {:error, "Missing environment variables for: #{Enum.join(missing_descriptions, ", ")}"}
    end
  end

  # Private helper functions

  defp get_user_google_accounts(user) do
    from(ga in GoogleAccount,
      where: ga.user_id == ^user.id,
      preload: [:user]
    )
    |> Repo.all()
  end

  defp get_user_social_connections(user) do
    from(sc in SocialConnection,
      where: sc.user_id == ^user.id,
      preload: [:user]
    )
    |> Repo.all()
  end

  defp format_google_token_status(%GoogleAccount{} = account) do
    %{
      type: "google",
      email: account.email,
      expires_at: account.expires_at,
      needs_refresh: needs_refresh?(account),
      has_refresh_token: not is_nil(account.refresh_token),
      time_until_expiry: time_until_expiry(account.expires_at)
    }
  end

  defp format_social_token_status(%SocialConnection{} = connection) do
    %{
      type: "social",
      platform: connection.platform,
      email: connection.email,
      expires_at: connection.expires_at,
      needs_refresh: needs_refresh?(connection),
      has_refresh_token: not is_nil(connection.refresh_token),
      time_until_expiry: time_until_expiry(connection.expires_at)
    }
  end

  defp check_expiry(expires_at) do
    buffer_time = DateTime.add(DateTime.utc_now(), :timer.minutes(10), :millisecond)
    DateTime.compare(expires_at, buffer_time) != :gt
  end

  defp time_until_expiry(nil), do: nil

  defp time_until_expiry(expires_at) do
    case DateTime.diff(expires_at, DateTime.utc_now(), :second) do
      diff when diff > 0 -> "#{div(diff, 3600)} hours, #{rem(div(diff, 60), 60)} minutes"
      _ -> "Expired"
    end
  end

  defp analyze_tokens(tokens, expiry_extractor) do
    now = DateTime.utc_now()

    {valid_tokens, expired_tokens, expiring_soon} =
      Enum.reduce(tokens, {0, 0, 0}, fn token, {valid, expired, expiring} ->
        case expiry_extractor.(token) do
          nil ->
            {valid, expired, expiring}

          expires_at ->
            diff = DateTime.diff(expires_at, now, :second)

            cond do
              diff <= 0 -> {valid, expired + 1, expiring}
              # Expiring within 1 hour
              diff <= 3600 -> {valid, expired, expiring + 1}
              true -> {valid + 1, expired, expiring}
            end
        end
      end)

    %{
      total: length(tokens),
      valid: valid_tokens,
      expired: expired_tokens,
      expiring_soon: expiring_soon,
      health_score: calculate_health_score(valid_tokens, expired_tokens, expiring_soon)
    }
  end

  defp extract_google_expiry(%GoogleAccount{expires_at: expires_at}), do: expires_at
  defp extract_social_expiry(%SocialConnection{expires_at: expires_at}), do: expires_at

  defp calculate_health_score(valid, expired, expiring) do
    total = valid + expired + expiring
    if total == 0, do: 100, else: round(valid / total * 100)
  end
end
