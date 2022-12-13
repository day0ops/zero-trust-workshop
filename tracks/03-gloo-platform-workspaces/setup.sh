#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Enforce strict mTLS
kubectl --context $WEST_CONTEXT apply -n istio-config -f $DIR/strict-mtls.yaml
kubectl --context $EAST_CONTEXT apply -n istio-config -f $DIR/strict-mtls.yaml