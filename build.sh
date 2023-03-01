#!/bin/bash

# stop when error or non-existent variable happen, show debug info
set -eux

# build new image
docker build -t registry.fly.io/sichat:v0.1 .

# publish the image
docker push registry.fly.io/sichat:v0.1

# get the current machine id
if MID=$(flyctl machine list -a sichat | grep -o -E "[A-Fa-f0-9]{14}"); then
    # stop the machine and wait till it is stopped
    flyctl machine stop "$MID" -a sichat
    sleep 10

    # rm and wait till it is removed and volume is ready to be attached again
    fly machine remove "$MID" -a sichat
    sleep 10
fi

# run a new machine
flyctl machine run registry.fly.io/sichat:v0.1 -a sichat -p 443:6167/tcp:tls:http -p 80:6167/tcp:http --name matrix-servere --region lax --volume conduit_data:/var/lib/matrix-conduit

# test
curl -i https://sichat.io/_matrix/client/versions
