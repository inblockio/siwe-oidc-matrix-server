#!/bin/bash

if [ "$MATRIX_USE_BUILDIN_SIWEOIDC" == "true" ]
then
export AUTHLIB_INSECURE_TRANSPORT=true
fi


if [ ! -f /data/homeserver.yaml ]; then

/start.py generate

#general
yq -i --unwrapScalar=false ".server_name =\"${MATRIX_HOST}\")" /data/homeserver.yaml
yq -i ".listeners[0].port = ${MATRIX_PORT}" /data/homeserver.yaml
yq -i ".public_baseurl = \"${MATRIX_BASE_URL}\"" /data/homeserver.yaml



#oidc-config
yq -i ".oidc_providers[0].idp_id = \"siwe-oidc\"" /data/homeserver.yaml
yq -i ".oidc_providers[0].idp_name = \"siwe-oidc\"" /data/homeserver.yaml
yq -i ".oidc_providers[0].idp_brand = \"siwe-oidc\"" /data/homeserver.yaml

#retention
yq -i ".retention.enabled=true" /data/homeserver.yaml
yq -i ".retention.default_policy.allowed_lifetime_max= \"${MATRIX_MESSAGE_LIFETIME}\"" /data/homeserver.yaml

if [ "$MATRIX_USE_BUILDIN_SIWEOIDC" == "true" ]
then
  yq -i ".oidc_providers[0].issuer = \"http://siwe-oidc:${SIWEOIDC_PORT}\"" /data/homeserver.yaml
  yq -i ".oidc_providers[0].token_endpoint = \"http://siwe-oidc:${SIWEOIDC_PORT}/token\"" /data/homeserver.yaml
  yq -i ".oidc_providers[0].userinfo_endpoint = \"http://siwe-oidc:${SIWEOIDC_PORT}/userinfo\"" /data/homeserver.yaml
  yq -i ".oidc_providers[0].jwks_uri = \"http://siwe-oidc:${SIWEOIDC_PORT}/jwk\"" /data/homeserver.yaml
else
  yq -i ".oidc_providers[0].issuer = \"${SIWEOIDC_BASE_URL}\"" /data/homeserver.yaml
fi
yq -i ".oidc_providers[0].client_id = \"${MATRIX_OIDC_CLIENT_ID}\"" /data/homeserver.yaml
yq -i ".oidc_providers[0].client_secret = \"${MATRIX_OIDC_SECRET_ID}\"" /data/homeserver.yaml

yq -i ".oidc_providers[0].client_auth_method = \"client_secret_post\"" /data/homeserver.yaml
yq -i ".oidc_providers[0].user_profile_method = \"userinfo_endpoint\"" /data/homeserver.yaml


else
  echo "Setup already complete! Skipping Setup"
fi

/start.py
