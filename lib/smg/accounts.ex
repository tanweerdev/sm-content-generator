defmodule SMG.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias SMG.Repo

  alias SMG.Accounts.{User, GoogleAccount}

  @doc """
  Gets a single user.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Creates a user.
  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates or updates a user with Google account information.
  """
  def upsert_user_with_google_account(user_params, google_params) do
    Repo.transaction(fn ->
      # First, try to find existing user by email
      user =
        case get_user_by_email(user_params.email) do
          nil ->
            case create_user(user_params) do
              {:ok, user} -> user
              {:error, changeset} -> Repo.rollback(changeset)
            end

          existing_user ->
            case update_user(existing_user, user_params) do
              {:ok, user} -> user
              {:error, changeset} -> Repo.rollback(changeset)
            end
        end

      # Now handle the Google account
      google_params = Map.put(google_params, :user_id, user.id)

      case get_google_account_by_google_user_id(google_params.google_user_id) do
        nil ->
          case create_google_account(google_params) do
            {:ok, _google_account} -> user
            {:error, changeset} -> Repo.rollback(changeset)
          end

        existing_google_account ->
          case update_google_account(existing_google_account, google_params) do
            {:ok, _google_account} -> user
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
  end

  @doc """
  Gets a google account by google_user_id.
  """
  def get_google_account_by_google_user_id(google_user_id) do
    Repo.get_by(GoogleAccount, google_user_id: google_user_id)
  end

  @doc """
  Creates a google account.
  """
  def create_google_account(attrs \\ %{}) do
    %GoogleAccount{}
    |> GoogleAccount.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a google account.
  """
  def update_google_account(%GoogleAccount{} = google_account, attrs) do
    google_account
    |> GoogleAccount.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists all google accounts for a user.
  """
  def list_user_google_accounts(%User{} = user) do
    Repo.all(from g in GoogleAccount, where: g.user_id == ^user.id)
  end

  @doc """
  Gets a user with preloaded google accounts.
  """
  def get_user_with_google_accounts(id) do
    Repo.get(User, id)
    |> Repo.preload(:google_accounts)
  end

  @doc """
  Gets a google account by id.
  """
  def get_google_account(id) do
    Repo.get(GoogleAccount, id)
    |> Repo.preload(:user)
  end

  @doc """
  Deletes a google account.
  """
  def delete_google_account(%GoogleAccount{} = google_account) do
    Repo.delete(google_account)
  end

  @doc """
  Creates or updates a google account based on google_user_id.
  """
  def create_or_update_google_account(attrs) when is_map(attrs) do
    google_user_id = attrs[:google_user_id] || attrs["google_user_id"]

    case get_google_account_by_google_user_id(google_user_id) do
      nil ->
        # Create new account
        %GoogleAccount{}
        |> GoogleAccount.changeset(attrs)
        |> Repo.insert()

      existing_account ->
        # Update existing account
        existing_account
        |> GoogleAccount.changeset(attrs)
        |> Repo.update()
    end
  end
end
