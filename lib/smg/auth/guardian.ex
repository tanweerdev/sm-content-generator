defmodule SMG.Auth.Guardian do
  @moduledoc """
  Guardian implementation for JWT token-based authentication.
  Provides secure session management and prevents user session conflicts.
  """
  use Guardian, otp_app: :cgenerator

  alias SMG.Accounts
  alias SMG.Accounts.User

  @doc """
  Encode the user ID into the JWT token subject
  """
  def subject_for_token(%User{id: id}, _claims) do
    {:ok, to_string(id)}
  end

  def subject_for_token(_, _) do
    {:error, :reason_for_error}
  end

  @doc """
  Decode the user from the JWT token subject
  """
  def resource_from_claims(%{"sub" => id}) do
    case Accounts.get_user(id) do
      nil -> {:error, :resource_not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_claims) do
    {:error, :reason_for_error}
  end

  @doc """
  Generate token and refresh token for user
  """
  def authenticate(user) do
    with {:ok, token, claims} <- encode_and_sign(user),
         {:ok, refresh_token, _claims} <- encode_and_sign(user, %{}, token_type: :refresh) do
      {:ok, %{token: token, refresh_token: refresh_token, user: user, claims: claims}}
    end
  end

  @doc """
  Exchange refresh token for new access token
  """
  def exchange_refresh_token(refresh_token) do
    with {:ok, _old_stuff, {token, new_claims}} <- exchange(refresh_token, "refresh", "access") do
      {:ok, %{token: token, claims: new_claims}}
    end
  end

  @doc """
  Revoke token to log out user
  """
  def revoke_token(token) do
    revoke(token)
  end

  @doc """
  Get user from token
  """
  def get_user_from_token(token) do
    case decode_and_verify(token) do
      {:ok, claims} -> resource_from_claims(claims)
      {:error, _reason} = error -> error
    end
  end
end
