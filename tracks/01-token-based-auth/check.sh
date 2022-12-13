#!/bin/bash

set -e

kubectl --context $WEST_CONTEXT get authconfig vault-oidc-auth-httpbin-west-cluster-ext-auth-service -n gloo-mesh-addons || fail-message "Could not find the vault-oidc-auth-httpbin-west-cluster-ext-auth-service AuthConfig in the gloo-mesh-addons namespace in the west cluster"

kubectl --context $WEST_CONTEXT get configmap only-allow-operators -n httpbin || fail-message "Could not find the only-allow-operators configmap in the httpbin namespace in the west cluster"