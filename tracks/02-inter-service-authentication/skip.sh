#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

kubectl --context $WEST_CONTEXT create ns httpbin-trusted
istioctl --context $WEST_CONTEXT kube-inject -r $ISTIO_REVISION -f $DIR/../../install/apps/httpbin/httpbin.yaml | kubectl --context $WEST_CONTEXT apply -n httpbin-trusted -f -

kubectl --context $WEST_CONTEXT create ns http-client-trusted
istioctl --context $WEST_CONTEXT kube-inject -r $ISTIO_REVISION -f $DIR/../../install/apps/http-client/http-client.yaml | kubectl --context $WEST_CONTEXT apply -n http-client-trusted -f -

sleep 5