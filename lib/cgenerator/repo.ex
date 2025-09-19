defmodule SMG.Repo do
  use Ecto.Repo,
    otp_app: :cgenerator,
    adapter: Ecto.Adapters.Postgres
end
