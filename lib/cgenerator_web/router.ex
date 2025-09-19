defmodule SMGWeb.Router do
  use SMGWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SMGWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug SMGWeb.AuthPlug
  end

  pipeline :require_auth do
    plug SMGWeb.AuthPlug, :require_auth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/auth", SMGWeb do
    pipe_through :browser

    get "/logout", AuthController, :logout
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/", SMGWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", SMGWeb do
    pipe_through [:browser, :require_auth]

    live_session :require_auth, on_mount: {SMGWeb.AuthOnMount, :ensure_authenticated} do
      live "/dashboard", DashboardLive
      live "/posts/:id", SocialPostLive
    end
  end

  # Webhook endpoints
  scope "/webhooks", SMGWeb do
    pipe_through :api

    post "/recall", WebhookController, :recall
  end

  # Other scopes may use custom stacks.
  # scope "/api", SMGWeb do
  #   pipe_through :api
  # end
end
