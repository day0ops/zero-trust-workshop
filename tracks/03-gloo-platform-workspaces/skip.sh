#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Step 1 - Workspaces
envsubst < <(cat $DIR/workspaces.yaml) | kubectl --context ${MGMT_CONTEXT} apply -n gloo-mesh -f -

# Step 2 - Workspace settings
envsubst < <(cat $DIR/workspace-settings-ops-team.yaml) | kubectl --context ${MGMT_CONTEXT} apply -n ops-team -f -
envsubst < <(cat $DIR/workspace-settings-web-team.yaml) | kubectl --context ${MGMT_CONTEXT} apply -n web-team -f -
envsubst < <(cat $DIR/workspace-settings-backend-apis-team.yaml) | kubectl --context ${MGMT_CONTEXT} apply -n backend-apis-team -f -
kubectl --context ${MGMT_CONTEXT} apply -n web-team -f $DIR/deny-all-web-team.yaml
kubectl --context ${MGMT_CONTEXT} apply -n backend-apis-team -f $DIR/deny-all-backend-apis-team.yaml

# Step 3 - Ingress
envsubst < <(cat $DIR/tls/certificate-issuer.yaml) | kubectl --context ${WEST_CONTEXT} apply -n istio-ingress -f -
envsubst < <(cat $DIR/tls/certificate.yaml) | kubectl --context ${WEST_CONTEXT} apply -n istio-ingress -f -
envsubst < <(cat $DIR/virtual-gateway.yaml) | kubectl --context ${MGMT_CONTEXT} apply -n ops-team -f -
envsubst < <(cat $DIR/route-table.yaml) | kubectl --context ${MGMT_CONTEXT} apply -n web-team -f -

# Step 4 - Apply Zero Trust
kubectl --context ${MGMT_CONTEXT} apply -n web-team -f /workshop/tracks/03-workspaces/access-policy-web-team.yaml
kubectl --context ${MGMT_CONTEXT} apply -n backend-apis-team -f /workshop/tracks/03-workspaces/access-policy-backend-apis-team.yaml
