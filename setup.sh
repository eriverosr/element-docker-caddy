#!/bin/bash

set -e
set -x

# set up data & secrets dir with the right ownerships in the default location
# to stop docker autocreating them with random owners.
# originally these were checked into the git repo, but that's pretty ugly, so doing it here instead.
mkdir -p data/{element-{web,call},livekit,mas,www,postgres,synapse}
mkdir -p secrets/{livekit,postgres,synapse}

# create blank secrets to avoid docker creating empty directories in the host
touch secrets/livekit/livekit_{api,secret}_key \
      secrets/postgres/postgres_password \
      secrets/synapse/signing.key

# grab an env if we don't have one already
if [[ ! -e .env  ]]; then
    cp .env-sample .env

    sed -ri.orig "s/^USER_ID=/USER_ID=$(id -u)/" .env
    sed -ri.orig "s/^GROUP_ID=/GROUP_ID=$(id -g)/" .env

    read -p "Enter base domain name (e.g. example.com): " DOMAIN
    sed -ri.orig "s/example.com/$DOMAIN/" .env

    # try to guess your livekit IP
    if [ -x "$(command -v getent)" ]; then
        NODE_IP=`getent hosts livekit.$DOMAIN | cut -d' ' -f1`
        if ! [ -z "$NODE_IP" ]; then
            sed -ri.orig "s/LIVEKIT_NODE_IP=127.0.0.1/LIVEKIT_NODE_IP=$NODE_IP/" .env
        fi
    fi

    set -a
    source .env
    set +a

    # create-synapse-secrets
    docker run --rm --env-file .env \
                -v ./data/synapse:/data \
                -v ./init/generate-synapse-secrets.sh:/entrypoint.sh \
                -e SYNAPSE_CONFIG_DIR=/data \
                -e SYNAPSE_CONFIG_PATH=/data/homeserver.yaml.default \
                -e SYNAPSE_SERVER_NAME=${DOMAIN} \
                -e SYNAPSE_REPORT_STATS=${REPORT_STATS} \
                -u $USER_ID:$GROUP_ID \
                --entrypoint /entrypoint.sh \
                ghcr.io/element-hq/synapse:latest

    # create-mas-secrets
    docker run --rm --env-file .env \
                -v ./data/mas:/data:rw \
                -u $USER_ID:$GROUP_ID \
                ghcr.io/element-hq/matrix-authentication-service:latest \
                config generate -o /data/config.yaml.default

    # init
    docker run --rm --env-file .env \
                -v ./secrets:/secrets \
                -v ./data:/data \
                -v ./data-template:/data-template \
                -v ./init/init.sh:/init.sh \
                -u $USER_ID:$GROUP_ID \
                alpine:latest \
                /init.sh
    

else
    echo ".env already exists; move it out of the way first to re-setup"
fi

if ! [ -z "$success" ]; then
    echo ".env and configfiles configured; you can now docker compose up"
fi
