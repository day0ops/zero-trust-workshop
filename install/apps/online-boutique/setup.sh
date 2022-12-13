#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

debug() {
    if [[ "$_DEBUG" = true ]]; then
        echo "$1"
    fi
}

debug "Setting up online boutique application"
envsubst < <(cat $DIR/web-ui.yaml) | kubectl --context $WEST_CONTEXT apply -n web-ui -f -
envsubst < <(cat $DIR/backend-apis.yaml) | kubectl --context $WEST_CONTEXT apply -n backend-apis -f -
envsubst < <(cat $DIR/checkout-feature.yaml) | kubectl --context $EAST_CONTEXT apply -n backend-apis -f -
# envsubst < <(cat $DIR/default-deny.yaml) | kubectl --context $EAST_CONTEXT apply -n backend-apis -f -