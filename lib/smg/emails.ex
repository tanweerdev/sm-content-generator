defmodule SMG.Emails do
  @moduledoc """
  The Emails context.
  """

  import Ecto.Query, warn: false
  alias SMG.Repo

  alias SMG.Emails.EmailContent

  @doc """
  Returns the list of email_contents.

  ## Examples

      iex> list_email_contents()
      [%EmailContent{}, ...]

  """
  def list_email_contents do
    Repo.all(EmailContent)
  end

  @doc """
  Returns the list of email_contents for a specific user.

  ## Examples

      iex> list_email_contents_by_user(user)
      [%EmailContent{}, ...]

  """
  def list_email_contents_by_user(user) do
    EmailContent
    |> where([e], e.user_id == ^user.id)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the list of email_contents for a specific calendar event.

  ## Examples

      iex> list_email_contents_by_event(event)
      [%EmailContent{}, ...]

  """
  def list_email_contents_by_event(event) do
    EmailContent
    |> where([e], e.calendar_event_id == ^event.id)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single email_content.

  Raises `Ecto.NoResultsError` if the Email content does not exist.

  ## Examples

      iex> get_email_content!(123)
      %EmailContent{}

      iex> get_email_content!(456)
      ** (Ecto.NoResultsError)

  """
  def get_email_content!(id), do: Repo.get!(EmailContent, id)

  @doc """
  Creates a email_content.

  ## Examples

      iex> create_email_content(%{field: value})
      {:ok, %EmailContent{}}

      iex> create_email_content(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_email_content(attrs \\ %{}) do
    %EmailContent{}
    |> EmailContent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a email_content.

  ## Examples

      iex> update_email_content(email_content, %{field: new_value})
      {:ok, %EmailContent{}}

      iex> update_email_content(email_content, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_email_content(%EmailContent{} = email_content, attrs) do
    email_content
    |> EmailContent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a email_content.

  ## Examples

      iex> delete_email_content(email_content)
      {:ok, %EmailContent{}}

      iex> delete_email_content(email_content)
      {:error, %Ecto.Changeset{}}

  """
  def delete_email_content(%EmailContent{} = email_content) do
    Repo.delete(email_content)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking email_content changes.

  ## Examples

      iex> change_email_content(email_content)
      %Ecto.Changeset{data: %EmailContent{}}

  """
  def change_email_content(%EmailContent{} = email_content, attrs \\ %{}) do
    EmailContent.changeset(email_content, attrs)
  end
end