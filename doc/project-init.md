# Project Initialization

This document describes the process to run Conduit in Fly.io. It is based on Conduit v0.5.0 source code.

## 1 Setup Repository

Clone the latest stable version without history code.

`git clone -b v0.5.0 --depth 1 https://gitlab.com/famedly/conduit.git`

Then delete all `.git` and `.gitlab` related folder. Initialize the repository:

`git add -A`
`git commit -m "initialized with v0.5.0 without history"`

After creating the `matrix-server` repo in GitHub, push it

`git remote add origin https://github.com/sichat-io/matrix-server.git`

Work on a dev branch.
`git checkout -b dev`.

## 2 Run in Local Docker Container

Change the `Dockerfile` as the following:

```dockerfile
# syntax=docker/dockerfile:1

FROM docker.io/rust:1.64-bullseye AS builder
WORKDIR /app

# Install required packages to build Conduit and it's dependencies
RUN apt-get update && \
    apt-get -y --no-install-recommends install libclang-dev=1:11.0-51+nmu5

# Copy over actual Conduit sources
COPY Cargo.toml Cargo.lock ./
COPY src src

RUN --mount=type=cache,target=/app/target \
    set -eux; \
    cargo build --release; \
    objcopy --compress-debug-sections target/release/conduit ./conduit


# Stuff below this line actually ends up in the resulting docker image
FROM docker.io/debian:bullseye-slim AS runner

ARG DEFAULT_DB_PATH=/var/lib/matrix-conduit

ENV CONDUIT_PORT=6167 \
    CONDUIT_SERVER_NAME="sichat.io" \
    CONDUIT_DATABASE_BACKEND="sqlite" \
    CONDUIT_ALLOW_REGISTRATION='true' \
    CONDUIT_ADDRESS="0.0.0.0" \
    CONDUIT_DATABASE_PATH=${DEFAULT_DB_PATH} \
    CONDUIT_CONFIG=''
#    └─> empty string '' sets no config file to do all configuration with env vars

EXPOSE ${CONDUIT_PORT}

# Set container home directory
WORKDIR /app

# Install conduit.deb:
COPY --from=builder /app/conduit ./conduit

# Improve security: Don't run stuff as root, that does not need to run as root
# Most distros also use 1000:1000 for the first real user, so this should resolve volume mounting problems.
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN set -x ; \
    groupadd -r -g ${GROUP_ID} conduit ; \
    useradd -l -r -M -d /srv/conduit -o -u ${USER_ID} -g conduit conduit && exit 0 ; exit 1

# Create database directory, change ownership of Conduit files to conduit user and group and make the healthcheck executable:
RUN chown -cR conduit:conduit /app/conduit && \
    mkdir -p ${DEFAULT_DB_PATH} && \
    chown -cR conduit:conduit ${DEFAULT_DB_PATH}

# Change user to conduit, no root permissions afterwards:
USER conduit

# Run Conduit and print backtraces on panics
ENV RUST_BACKTRACE=1
ENTRYPOINT [ "./conduit" ]
```

The important changes are three settings: required server name, sqlite db and allow registration of new accounts.

```dockerfile
CONDUIT_SERVER_NAME="sichat.io" \
CONDUIT_DATABASE_BACKEND="sqlite" \
CONDUIT_ALLOW_REGISTRATION='true' \
```

Built a docker image `docker build -t conduit .`
Run `docker run --name conduit -d -p 6167:6167 conduit`
Test the server is up and running: `curl -i http://0:6167/_matrix/client/versions`. It should show something like `{"versions":["r0.5.0","r0.6.0","v1.1","v1.2"],"unstable_features":{"org.matrix.e2e_cross_signing":true}}` after the HTTP headers. Https doesn't work locally.

## 3 Run in Fly.io

First, create a fly app and a volume.

```sh
flyctl apps create sichat --machines
fly ips allocate-v4 --shared -a sichat
fly ips allocate-v6 -a sichat
fly volumes create conduit_data --no-encryption --region lax --size 1 -a sichat
```

Then, build and run the image in a fly machine:

- build docker image: `docker build -t registry.fly.io/sichat:v0.1 .`
- publish docker image: `docker push registry.fly.io/sichat:v0.1`
- run a machine with the data valume: `flyctl machine run registry.fly.io/sichat:v0.1 -a sichat -p 443:6167/tcp:tls:http -p 80:6167/tcp:http --name conduit-m01 --region lax --volume conduit_data:/var/lib/matrix-conduit`
- test `curl -i https://sichat.fly.dev/_matrix/client/versions`
