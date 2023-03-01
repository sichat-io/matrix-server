# syntax=docker/dockerfile:1

# Use https://github.com/LukeMathWalker/cargo-chef to cache dependencies
FROM lukemathwalker/cargo-chef:latest-rust-1 AS chef
WORKDIR /app

# Install required packages to build Conduit and it's dependencies
RUN apt-get update && \
    apt-get -y --no-install-recommends install libclang-dev=1:11.0-51+nmu5

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
# Build dependencies - this is the caching Docker layer!
RUN cargo chef cook --release --recipe-path recipe.json

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
    CONDUIT_ALLOW_REGISTRATION="true" \
    CONDUIT_LOG="info,state_res=info,_=off,sled=off" \
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
