#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

kubectl --context $WEST_CONTEXT create ns httpbin
kubectl --context $WEST_CONTEXT apply -f $DIR/../../install/apps/httpbin/httpbin.yaml -n httpbin

# ------------------------------
# TLS
# ------------------------------
envsubst < <(cat $DIR/tls/certificate-issuer.yaml) | kubectl --context $WEST_CONTEXT apply -f -
envsubst < <(cat $DIR/tls/certificate.yaml) | kubectl --context $WEST_CONTEXT apply -f -

sleep 5

export ACME_SOLVER_TOKEN=$(kubectl --context $WEST_CONTEXT get orders -n istio-ingress -o jsonpath='{.items[].status.authorizations[0].challenges[?(@.type=="http-01")].token}')
export ACME_SOLVER_SERVICE=$(kubectl --context $WEST_CONTEXT get svc -n istio-ingress --selector=acme.cert-manager.io/http01-solver=true -o jsonpath='{.items[].metadata.name}')

envsubst < <(cat $DIR/tls/acme-solver-routetable.yaml) | kubectl --context $WEST_CONTEXT apply -f -
envsubst < <(cat $DIR/tls/acme-solver-virtual-gw.yaml) | kubectl --context $WEST_CONTEXT apply -f -

sleep 5

envsubst < <(cat $DIR/tls/httpbin-routetable.yaml) | kubectl --context $WEST_CONTEXT apply -f -
envsubst < <(cat $DIR/tls/httpbin-virtual-gw.yaml) | kubectl --context $WEST_CONTEXT apply -f -

# ------------------------------
# AuthN
# ------------------------------
vault auth enable userpass

vault write auth/userpass/users/dev \
    password="password" \
    token_ttl="1h"

vault write identity/entity \
    name="dev" \
    metadata="email=dev@example.com" \
    disabled=false

DEV_ENTITY_ID=$(vault read -field=id identity/entity/name/dev)

vault write identity/group \
    name="developers" \
    member_entity_ids="${DEV_ENTITY_ID}"

DEV_GROUP_ID=$(vault read -field=id identity/group/name/developers)

USERPASS_ACCESSOR=$(vault auth list -detailed -format json | jq -r '.["userpass/"].accessor')

vault write identity/entity-alias \
    name="dev" \
    canonical_id="${DEV_ENTITY_ID}" \
    mount_accessor="${USERPASS_ACCESSOR}"

vault write auth/userpass/users/ops \
    password="password" \
    token_ttl="1h"

vault write identity/entity \
    name="ops" \
    metadata="email=ops@example.com" \
    disabled=false

OPS_ENTITY_ID=$(vault read -field=id identity/entity/name/ops)

vault write identity/group \
    name="operators" \
    member_entity_ids="${OPS_ENTITY_ID}"

OPS_GROUP_ID=$(vault read -field=id identity/group/name/operators)

vault write identity/entity-alias \
    name="ops" \
    canonical_id="${OPS_ENTITY_ID}" \
    mount_accessor="${USERPASS_ACCESSOR}"

vault write identity/oidc/assignment/gloo-assignment \
    entity_ids="${DEV_ENTITY_ID}, ${OPS_ENTITY_ID}" \
    group_ids="${DEV_GROUP_ID}, ${OPS_GROUP_ID}"

vault write identity/oidc/key/gloo-key \
    allowed_client_ids="*" \
    verification_ttl="2h" \
    rotation_period="1h" \
    algorithm="RS256"

# Creating the OIDC client `gloo`
vault write identity/oidc/client/gloo \
    redirect_uris="https://${PUBLIC_INSTRUQT_SANDBOX_ENDPOINT}/login" \
    assignments="gloo-assignment" \
    key="gloo-key" \
    id_token_ttl="30m" \
    access_token_ttl="1h"

# Grab the client ID
export AUTH_CLIENT_ID=$(vault read -field=client_id identity/oidc/client/gloo)

USER_SCOPE_TEMPLATE='{
    "username": {{identity.entity.name}},
    "contact": {
        "email": {{identity.entity.metadata.email}}
    }
}'
vault write identity/oidc/scope/user \
    description="The user scope provides claims using Vault identity entity metadata" \
    template="$(echo ${USER_SCOPE_TEMPLATE} | base64 -)"

# Group scope
GROUPS_SCOPE_TEMPLATE='{
    "groups": {{identity.entity.groups.names}}
}'
vault write identity/oidc/scope/groups \
    description="The groups scope provides the groups claim using Vault group membership" \
    template="$(echo ${GROUPS_SCOPE_TEMPLATE} | base64 -)"

# Create the provider
vault write identity/oidc/provider/gloo-provider \
    allowed_client_ids="${AUTH_CLIENT_ID}" \
    scopes_supported="groups,user" \
    issuer="${VAULT_ADDR}"

export ISSUER=$(curl -s $VAULT_ADDR/v1/identity/oidc/provider/gloo-provider/.well-known/openid-configuration | jq -r .issuer)

export CLIENT_SECRET=$(vault read -field=client_secret identity/oidc/client/gloo)

export CLIENT_SECRET_ENCODED=$(echo -n ${CLIENT_SECRET} | base64 -w0)
envsubst < <(cat $DIR/auth/client-secret.yaml) | kubectl --context $WEST_CONTEXT apply -f -
envsubst < <(cat $DIR/auth/ext-auth-server.yaml) | kubectl --context $WEST_CONTEXT apply -f -
envsubst < <(cat $DIR/auth/auth-config.yaml) | kubectl --context $WEST_CONTEXT apply -f -
envsubst < <(cat $DIR/auth/httpbin-routetable.yaml) | kubectl --context $WEST_CONTEXT apply -f -

# ------------------------------
# AuthZ
# ------------------------------
kubectl --context $WEST_CONTEXT create configmap only-allow-operators -n httpbin --from-file=$DIR/auth/policy.rego
envsubst < <(cat $DIR/auth/auth-config-opa.yaml) | kubectl --context $WEST_CONTEXT apply -f -