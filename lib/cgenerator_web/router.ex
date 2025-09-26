defmodule SMGWeb.Router do
  use SMGWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SMGWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug SMGWeb.GuardianAuthPlug
  end

  pipeline :guardian_auth do
    plug Guardian.Plug.Pipeline,
      module: SMG.Auth.Guardian,
      error_handler: SMGWeb.GuardianErrorHandler

    plug Guardian.Plug.VerifySession
    plug Guardian.Plug.VerifyHeader, realm: "Bearer"
    plug Guardian.Plug.LoadResource, allow_blank: true
  end

  pipeline :auth do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :put_root_layout, html: {SMGWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :require_auth do
    plug SMGWeb.GuardianAuthPlug, :require_auth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/auth", SMGWeb do
    pipe_through :auth

    get "/logout", AuthController, :logout
    get "/clear", AuthController, :clear_session
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    get "/linkedin/custom", LinkedInAuthController, :authorize
  end

  scope "/", SMGWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/test-login", AuthController, :test_login
  end

  scope "/", SMGWeb do
    pipe_through [:browser, :guardian_auth, :require_auth]

    live_session :require_auth, on_mount: {SMGWeb.AuthOnMount, :ensure_authenticated} do
      live "/dashboard", DashboardLive
      live "/meetings", MeetingsLive
      live "/meetings/:id", MeetingDetailLive
      live "/posts/:id", SocialPostLive
      live "/settings", SettingsLive
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
