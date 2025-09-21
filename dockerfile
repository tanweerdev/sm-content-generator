# syntax = docker/dockerfile:1

FROM hexpm/elixir:1.15.4-erlang-26.0.2-debian-bullseye-20230612 AS build

# install build tools
RUN apt-get update -y && apt-get install -y build-essential git curl

# install node for asset building
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
  && apt-get install -y nodejs

WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

# set build ENV
ENV MIX_ENV=prod

# install mix deps
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# install npm deps
COPY assets assets
RUN cd assets && npm install

# build assets
RUN mix assets.deploy

# copy source
COPY lib lib
COPY priv priv

# compile app
RUN mix compile

# release
RUN mix release

# runtime image
FROM debian:bullseye-20230612-slim AS app
RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*
WORKDIR /app
RUN useradd -ms /bin/bash app
USER app
COPY --from=build /app/_build/prod/rel/cgenerator ./
CMD ["bin/cgenerator", "start"]
