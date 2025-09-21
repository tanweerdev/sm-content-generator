defmodule SMG.Services.OAuthTokenRefresher do
  @moduledoc """
  GenServer that periodically checks and refreshes OAuth tokens for all platforms
  (Google, Facebook, LinkedIn) before they expire.
  """

  use GenServer
  require Logger
  import Ecto.Query

  alias SMG.{Repo, Accounts, Settings}
  alias SMG.Accounts.GoogleAccount
  alias SMG.Settings.SocialConnection

  # Check every hour
  @refresh_interval :timer.hours(1)
  # Refresh tokens 10 minutes before expiry
  @refresh_buffer :timer.minutes(10)
  @max_retries 3

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule the first token check
    schedule_refresh()
    {:ok, %{retry_count: 0}}
  end

  @impl true
  def handle_info(:refresh_tokens, state) do
    Logger.info("Starting OAuth token refresh cycle")

    case refresh_expired_tokens() do
      {:ok, refreshed_count} ->
        Logger.info("Token refresh completed successfully", refreshed: refreshed_count)
        schedule_refresh()
        {:noreply, %{state | retry_count: 0}}

      {:error, reason} ->
        retry_count = state.retry_count + 1

        Logger.error("Token refresh failed",
          reason: reason,
          retry_count: retry_count,
          max_retries: @max_retries
        )

        if retry_count < @max_retries do
          # Retry with exponential backoff
          Process.send_after(self(), :refresh_tokens, 5_000 * retry_count)
          {:noreply, %{state | retry_count: retry_count}}
        else
          # Reset retry count and schedule next regular refresh
          Logger.error("Max retries reached, skipping this refresh cycle")
          schedule_refresh()
          {:noreply, %{state | retry_count: 0}}
        end
    end
  end

  @impl true
  def handle_call(:force_refresh, _from, state) do
    case refresh_expired_tokens() do
      {:ok, refreshed_count} ->
        {:reply, {:ok, refreshed_count}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def force_refresh do
    GenServer.call(__MODULE__, :force_refresh)
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh_tokens, @refresh_interval)
  end

  defp refresh_expired_tokens do
    try do
      # Get all tokens that are about to expire
      google_accounts = get_expiring_google_accounts()
      social_connections = get_expiring_social_connections()

      Logger.info("Found tokens to refresh",
        google_accounts: length(google_accounts),
        social_connections: length(social_connections)
      )

      # Refresh Google tokens
      google_results = Enum.map(google_accounts, &refresh_google_token/1)

      # Refresh social platform tokens
      social_results = Enum.map(social_connections, &refresh_social_token/1)

      # Count successful refreshes
      all_results = google_results ++ social_results

      successful_refreshes =
        all_results
        |> Enum.count(fn result ->
          case result do
            {:ok, _} -> true
            _ -> false
          end
        end)

      {:ok, successful_refreshes}
    rescue
      error ->
        Logger.error("Error during token refresh cycle", error: inspect(error))
        {:error, "Token refresh failed: #{inspect(error)}"}
    end
  end

  defp get_expiring_google_accounts do
    buffer_time = DateTime.add(DateTime.utc_now(), @refresh_buffer, :millisecond)

    from(ga in GoogleAccount,
      where:
        not is_nil(ga.refresh_token) and
          not is_nil(ga.expires_at) and
          ga.expires_at <= ^buffer_time,
      preload: [:user]
    )
    |> Repo.all()
  end

  defp get_expiring_social_connections do
    buffer_time = DateTime.add(DateTime.utc_now(), @refresh_buffer, :millisecond)

    from(sc in SocialConnection,
      where:
        not is_nil(sc.refresh_token) and
          not is_nil(sc.expires_at) and
          sc.expires_at <= ^buffer_time,
      preload: [:user]
    )
    |> Repo.all()
  end

  defp refresh_google_token(%GoogleAccount{} = account) do
    Logger.info("Refreshing Google token",
      user_id: account.user_id,
      expires_at: account.expires_at
    )

    case SMG.Integrations.GoogleAuth.refresh_token(account.refresh_token) do
      {:ok, token_data} ->
        update_attrs = %{
          access_token: token_data["access_token"],
          expires_at: DateTime.add(DateTime.utc_now(), token_data["expires_in"], :second)
        }

        # Add new refresh token if provided
        update_attrs =
          if token_data["refresh_token"] do
            Map.put(update_attrs, :refresh_token, token_data["refresh_token"])
          else
            update_attrs
          end

        case Accounts.update_google_account(account, update_attrs) do
          {:ok, updated_account} ->
            Logger.info("Successfully refreshed Google token",
              user_id: account.user_id,
              new_expires_at: updated_account.expires_at
            )

            {:ok, updated_account}

          {:error, changeset} ->
            Logger.error("Failed to update Google account with new token",
              user_id: account.user_id,
              errors: inspect(changeset.errors)
            )

            {:error, "Failed to update account: #{inspect(changeset.errors)}"}
        end

      {:error, reason} ->
        Logger.error("Failed to refresh Google token",
          user_id: account.user_id,
          reason: reason
        )

        {:error, reason}
    end
  end

  defp refresh_social_token(%SocialConnection{platform: platform} = connection) do
    Logger.info("Refreshing #{platform} token",
      user_id: connection.user_id,
      platform: platform,
      expires_at: connection.expires_at
    )

    case refresh_platform_token(platform, connection.refresh_token) do
      {:ok, token_data} ->
        update_attrs = %{
          access_token: token_data["access_token"],
          expires_at: DateTime.add(DateTime.utc_now(), token_data["expires_in"], :second)
        }

        # Add new refresh token if provided
        update_attrs =
          if token_data["refresh_token"] do
            Map.put(update_attrs, :refresh_token, token_data["refresh_token"])
          else
            update_attrs
          end

        case Settings.update_social_connection(connection, update_attrs) do
          {:ok, updated_connection} ->
            Logger.info("Successfully refreshed #{platform} token",
              user_id: connection.user_id,
              platform: platform,
              new_expires_at: updated_connection.expires_at
            )

            {:ok, updated_connection}

          {:error, changeset} ->
            Logger.error("Failed to update #{platform} connection with new token",
              user_id: connection.user_id,
              platform: platform,
              errors: inspect(changeset.errors)
            )

            {:error, "Failed to update connection: #{inspect(changeset.errors)}"}
        end

      {:error, reason} ->
        Logger.error("Failed to refresh #{platform} token",
          user_id: connection.user_id,
          platform: platform,
          reason: reason
        )

        {:error, reason}
    end
  end

  defp refresh_platform_token("facebook", refresh_token) do
    SMG.Integrations.FacebookAuth.refresh_token(refresh_token)
  end

  defp refresh_platform_token("linkedin", refresh_token) do
    SMG.Integrations.LinkedInAuth.refresh_token(refresh_token)
  end

  defp refresh_platform_token(platform, _refresh_token) do
    {:error, "Unsupported platform: #{platform}"}
  end
end
