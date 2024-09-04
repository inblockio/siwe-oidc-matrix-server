#!/bin/bash
SIWEOIDC_CLIENT_ID=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13; echo)
SIWEOIDC_SECRET_ID=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13; echo)
SIWEOIDC_HOST=localhost
SIWEOIDC_PORT=8081
SIWEOIDC_ADDRESS=0.0.0.0
SIWEOIDC_DEFAULT_CLIENTS=
USE_BUILDIN_SIWEOIDC=false
RUST_LOG="siwe_oidc=error,tower_http=error"
#TODO remove
SIWEOIDC_BASE_URL="http://$SIWEOIDC_HOST:$SIWEOIDC_PORT"
MATRIX_SERVER_NAME=localhost
MATRIX_HOST=localhost
MATRIX_PORT=8080
MATRIX_BASE_URL="http://$MATRIX_HOST:$MATRIX_PORT"
MATRIX_REPORT_STATS=no
MATRIX_MESSAGE_LIFETIME=4w
ATTACH=false



while [ "$#" -gt 0 ]; do
        case "$1" in
            --SIWEOIDC_CLIENT_ID)
                SIWEOIDC_CLIENT_ID="$2"
                shift
                shift
                ;;
            --SIWEOIDC_SECRET_ID)
                SIWEOIDC_SECRET_ID="$2"
                shift
                shift
                ;;
            --SIWEOIDC_HOST)
                SIWEOIDC_HOST="$2"
                shift
                shift
                ;;
            --SIWEOIDC_PORT)
                SIWEOIDC_PORT="$2"
                shift
                shift
                ;;
            --SIWEOIDC_DEFAULT_CLIENTS)
                SIWEOIDC_DEFAULT_CLIENTS="$2"
                shift
                shift
                ;;
            --SIWEOIDC_ADDRESS)
                SIWEOIDC_ADDRESS="$2"
                shift
                shift
                ;;
            --SIWEOIDC_BASE_URL)
                SIWEOIDC_BASE_URL="$2"
                shift
                shift
                ;;
            --ENABLE_DEBUG)
                RUST_LOG="siwe_oidc=debug,tower_http=trace"
                shift
                ;;
            --USE_BUILDIN_SIWEOIDC)
                USE_BUILDIN_SIWEOIDC=true
                shift
                ;;
            --MATRIX_SERVER_NAME)
                MATRIX_SERVER_NAME="$2"
                shift
                shift
                ;;
            --MATRIX_HOST)
                MATRIX_HOST="$2"
                shift
                shift
                ;;
            --MATRIX_PORT)
                MATRIX_PORT="$2"
                shift
                shift
                ;;
            --MATRIX_BASE_URL)
                MATRIX_BASE_URL="$2"
                shift
                shift
                ;;
            --MATRIX_MESSAGE_LIFETIME)
                MATRIX_MESSAGE_LIFETIME="$2"
                shift
                shift
                ;;
            --attach)
                ATTACH=true
                shift
                ;;
            --MATRIX_REPORT_STATS)
                MATRIX_REPORT_STATS=yes
                shift
                ;;
                *)
                  echo "unknown arg ${1}"
                exit 0
                ;;
        esac
    done

if test -z "$SIWEOIDC_DEFAULT_CLIENTS"
then
SIWEOIDC_DEFAULT_CLIENTS="'{$SIWEOIDC_CLIENT_ID=\"{\\\"secret\\\":\\\"$SIWEOIDC_SECRET_ID\\\", \\\"metadata\\\": {\\\"redirect_uris\\\": [\\\"$MATRIX_BASE_URL/_synapse/client/oidc/callback\\\"]}}\"}'"
fi

if [ ! -f ./.env ]; then
    touch .env
else
  rm .env
  touch .env
fi

echo "#SIWEOIDC-CONFIG" >> .env
echo "SIWEOIDC_ADDRESS=$SIWEOIDC_ADDRESS" >> .env
echo "SIWEOIDC_HOST=$SIWEOIDC_HOST" >> .env
echo "SIWEOIDC_PORT=$SIWEOIDC_PORT" >> .env
echo "SIWEOIDC_DEFAULT_CLIENTS=$SIWEOIDC_DEFAULT_CLIENTS" >> .env
echo "SIWEOIDC_BASE_URL=$SIWEOIDC_BASE_URL" >> .env
echo "RUST_LOG=$RUST_LOG" >> .env




echo "#MATRIX-CONFIG" >> .env
echo "MATRIX_OIDC_CLIENT_ID=$SIWEOIDC_CLIENT_ID" >> .env
echo "MATRIX_OIDC_SECRET_ID=$SIWEOIDC_SECRET_ID" >> .env
echo "MATRIX_USE_BUILDIN_SIWEOIDC=$USE_BUILDIN_SIWEOIDC" >> .env
echo "MATRIX_HOST=$MATRIX_HOST" >> .env
echo "MATRIX_PORT=$MATRIX_PORT" >> .env
echo "MATRIX_BASE_URL=$MATRIX_BASE_URL" >> .env
echo "MATRIX_REPORT_STATS=$MATRIX_REPORT_STATS" >> .env
echo "MATRIX_SERVER_NAME=$MATRIX_SERVER_NAME" >> .env
echo "MATRIX_MESSAGE_LIFETIME=$MATRIX_MESSAGE_LIFETIME" >> .env



if [ "$USE_BUILDIN_SIWEOIDC" = "true" ]
then
  if [ "$ATTACH" == "true" ]; then
    docker-compose up matrix_synapse redis siwe-oidc
  else
    docker-compose up matrix_synapse redis siwe-oidc -d
  fi
else
  if [ "$ATTACH" == "true" ]; then
      docker-compose up
  else
    docker-compose up -d
  fi
fi
