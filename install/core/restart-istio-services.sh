#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

error_exit() {
    echo "Error: $1"
    exit 1
}

print_operation_info() {
    echo "============================================================"
    echo "$1"
    echo "============================================================"
    echo ""
}

debug() {
    if [[ "$_DEBUG" = true ]]; then
        echo "$1"
    fi
}

wait_for_lb_address() {
    local context=$1
    local service=$2
    local ns=$3

    # Only run this for a load balancer type
    kubectl --context ${context} -n $ns get service/$service --output=jsonpath='{.spec.type}' | grep -i LoadBalancer &> /dev/null
    is_lb_enabled=$?
    if [ $is_lb_enabled -eq 0 ]; then
        ip=""
        while [ -z $ip ]; do
            echo "Waiting for $service external IP ..."
            ip=$(kubectl --context ${context} -n $ns get service/$service --output=jsonpath='{.status.loadBalancer}' | grep "ingress")
            [ -z "$ip" ] && sleep 5
        done
        debug "Found $service external IP: ${ip}"
    fi
}

restart() {
    local cluster_context=$1
    local cluster_name=$2

    print_operation_info "Restarting Istio services on $cluster_name cluster"

    # Restart control plane
    kubectl --context ${cluster_context} \
        -n istio-system rollout restart deploy/istiod-${ISTIO_REVISION}
    kubectl --context ${cluster_context} \
        -n istio-system rollout status deploy/istiod-${ISTIO_REVISION} --timeout=90s
    sleep 5

    # Restart all the gateways
    kubectl --context ${cluster_context} \
        -n istio-ingress rollout restart deploy/istio-ingressgateway 
    kubectl --context ${cluster_context} \
        -n istio-ingress rollout status deploy/istio-ingressgateway --timeout=90s
    wait_for_lb_address $cluster_context "istio-ingressgateway " "istio-ingress"
    kubectl --context ${cluster_context} \
        -n istio-eastwest rollout restart deploy/istio-eastwestgateway
    kubectl --context ${cluster_context} \
        -n istio-eastwest rollout status deploy/istio-eastwestgateway --timeout=90s
    wait_for_lb_address $cluster_context "istio-eastwestgateway" "istio-eastwest"

    # And the rest
    kubectl --context ${cluster_context} \
        -n gloo-mesh-addons rollout restart deploy/rate-limiter
    kubectl --context ${cluster_context} \
        -n gloo-mesh-addons rollout status deploy/rate-limiter --timeout=90s
    kubectl --context ${cluster_context} \
        -n gloo-mesh-addons rollout restart deploy/redis
    kubectl --context ${cluster_context} \
        -n gloo-mesh-addons rollout status deploy/redis --timeout=90s
    kubectl --context ${cluster_context} \
        -n gloo-mesh-addons rollout restart deploy/ext-auth-service
    kubectl --context ${cluster_context} \
        -n gloo-mesh-addons rollout status deploy/ext-auth-service --timeout=90s
}

if [[ -z "$1" ]]; then
    error_exit "Cluster context required!"
fi
if [[ -z "$2" ]]; then
    error_exit "Cluster name required!"
fi

if [[ -z "${ISTIO_REVISION}" ]]; then
    error_exit "Istio revision is not set, \$ISTIO_REVISION must be defined"
fi

restart $1 $2