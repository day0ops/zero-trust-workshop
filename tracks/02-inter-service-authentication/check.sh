#!/bin/bash

set -e

kubectl --context $WEST_CONTEXT get ns http-client-trusted || fail-message "Could not find the http-client-trusted namespace in the west cluster"
kubectl --context $WEST_CONTEXT get ns httpbin-trusted || fail-message "Could not find the httpbin-trusted namespace in the west cluster"