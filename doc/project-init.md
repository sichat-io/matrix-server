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

Change the [`Dockerfile`](../Dockerfile):

The important changes are three settings: required server name, sqlite db and allow registration of new accounts.

```dockerfile
CONDUIT_SERVER_NAME="sichat.io" \
CONDUIT_DATABASE_BACKEND="sqlite" \
CONDUIT_ALLOW_REGISTRATION='true' \
CONDUIT_LOG="info,state_res=info,_=off,sled=off" \
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

To add custom domain, check [Fly Custom Domain](https://fly.io/docs/app-guides/custom-domains-with-fly/).

## 4 Code Change

For code change, you need to stop and delete the current image before run the machine with the new image:

- stop the current machine: `flyctl machine stop <machine-id> -a sichat`
- remove the machine: `flyctl machine remove <machine-id> -a sichat`

Run the [build script](../build.sh) to test the code change.
