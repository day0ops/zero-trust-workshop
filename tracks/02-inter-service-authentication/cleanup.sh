#!/bin/bash

# Clean up existing default workspaces
kubectl --context $MGMT_CONTEXT delete workspaces one-for-all -n gloo-mesh
kubectl --context $MGMT_CONTEXT delete workspacesettings one-for-all -n gloo-mesh

# Clean up apps
kubectl --context $WEST_CONTEXT delete ns httpbin-untrusted
kubectl --context $WEST_CONTEXT delete ns http-client-untrusted

# Delete any policies
kubectl --context $WEST_CONTEXT delete authorizationpolicy allow-access-to-httpbin -n httpbin-trusted
kubectl --context $WEST_CONTEXT delete authorizationpolicy deny-access-to-httpbin -n httpbin-trusted