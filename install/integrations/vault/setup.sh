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

install_vault() {
    local context=$1

    print_operation_info "Installing Vault $VAULT_VERSION"

    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm repo update

    helm install vault hashicorp/vault -n vault \
        --kube-context ${context} \
        --version ${VAULT_VERSION} \
        --create-namespace \
        -f $DIR/vault-helm-values.yaml

    # Wait for vault to be ready
    kubectl --context ${context} wait --for=condition=ready pod vault-0 -n vault --timeout=90s

    wait_for_lb_address $context "vault" "vault"
}

if [[ -z "$1" ]]; then
    error_exit "Cluster context required!"
fi

# Validation
if [[ -z "${VAULT_VERSION}" ]]; then
    error_exit "Vault helm version is not, \$VAULT_VERSION must be defined"
fi

install_vault $1