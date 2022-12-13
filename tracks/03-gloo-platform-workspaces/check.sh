#!/bin/bash

set -e

kubectl --context $MGMT_CONTEXT get workspace ops-team -n gloo-mesh || fail-message "Could not find the ops-team Workspace in the gloo-mesh namespace in the management cluster"
kubectl --context $MGMT_CONTEXT get workspace web-team -n gloo-mesh || fail-message "Could not find the web-team Workspace in the gloo-mesh namespace in the management cluster"
kubectl --context $MGMT_CONTEXT get workspace backend-apis-team -n gloo-mesh || fail-message "Could not find the backend-apis-team Workspace in the gloo-mesh namespace in the management cluster"

# Workspace Settings
kubectl --context $MGMT_CONTEXT get workspacesettings ops-team -n ops-team || fail-message "Could not find the ops-team WorkspaceSettings in the ops-team namespace in the management cluster"
kubectl --context $MGMT_CONTEXT get workspacesettings web-team -n web-team || fail-message "Could not find the web-team WorkspaceSettings in the web-team namespace in the management cluster"
kubectl --context $MGMT_CONTEXT get workspacesettings backend-apis-team -n backend-apis-team || fail-message "Could not find the backend-apis-team WorkspaceSettings in the backend-apis-team namespace in the management cluster"

# Virtual Gateway and RouteTable
kubectl --context $WEST_CONTEXT get certificate north-south-gw-cert -n istio-ingress || fail-message "Could not find Certificate north-south-gw-cert in the istio-ingress in the west cluster"
kubectl --context $MGMT_CONTEXT get virtualgateway north-south-gw -n ops-team || fail-message "Could not find the VirtualGateway north-south-gw in the ops-team namespace in the management cluster"
kubectl --context $MGMT_CONTEXT get routetable frontend -n web-team || fail-message "Could not find the RouteTable frontend in the web-team namespace in the management cluster"

# Access policy
kubectl --context $MGMT_CONTEXT get AccessPolicy frontend-api-access -n backend-apis-team || fail-message "Could not find the AccessPolicy frontend-api-access in the backend-apis-team namespace in the management cluster"
kubectl --context $MGMT_CONTEXT get AccessPolicy in-namespace-access -n backend-apis-team || fail-message "Could not find the AccessPolicy in-namespace-access in the backend-apis-team namespace in the management cluster"
kubectl --context $MGMT_CONTEXT get AccessPolicy gateway-access -n web-team || fail-message "Could not find the AccessPolicy gateway-access in the web-team namespace in the management cluster"
kubectl --context $MGMT_CONTEXT get AccessPolicy in-namespace-access -n web-team || fail-message "Could not find the AccessPolicy in-namespace-access in the web-team namespace in the management cluster"
kubectl --context $MGMT_CONTEXT get AccessPolicy deny-all -n web-team || fail-message "Could not find the AccessPolicy deny-all in the web-team namespace in the management cluster"
kubectl --context $MGMT_CONTEXT get AccessPolicy deny-all -n backend-apis-team || fail-message "Could not find the AccessPolicy deny-all in the backend-apis-team namespace in the management cluster"