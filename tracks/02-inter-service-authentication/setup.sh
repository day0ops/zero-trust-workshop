#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

kubectl --context $WEST_CONTEXT delete peerauthentication default -n istio-config
kubectl --context $EAST_CONTEXT delete peerauthentication default -n istio-config