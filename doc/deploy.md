# Deployment

The server is deployed to fly.io.

First install `flyctl` using `brew install flyctl`; Then sign in with `flyctl auth login`

Just run [build.sh](../build.sh). It builds Docker image and push to fly.io registry. The [Dockerfile](../Dockerfile) uses the [cargo-chef crate](https://github.com/LukeMathWalker/cargo-chef) to cache the Docker build of dependencies.
