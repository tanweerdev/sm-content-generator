defmodule SMGWeb.WebhookController do
  use SMGWeb, :controller

  alias SMG.Integrations.RecallAI

  def recall(conn, params) do
    case RecallAI.process_webhook(params) do
      {:ok, message} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: message})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", message: reason})
    end
  end
end
