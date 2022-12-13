#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

kubectl --context $MGMT_CONTEXT apply -f $DIR/global-workspace.yaml
kubectl --context $MGMT_CONTEXT apply -f $DIR/global-workspace-settings.yaml