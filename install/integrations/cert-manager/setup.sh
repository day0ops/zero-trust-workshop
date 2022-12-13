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

install_cert_manager() {
    local cluster_context=$1

    print_operation_info "Installing Cert Manager $CERT_MANAGER_VERSION on ${cluster_context} cluster"

    helm repo add jetstack https://charts.jetstack.io
    helm repo update

    kubectl --context ${cluster_context} \
        apply -f https://github.com/cert-manager/cert-manager/releases/download/$CERT_MANAGER_VERSION/cert-manager.crds.yaml

    helm install cert-manager jetstack/cert-manager -n cert-manager \
        --kube-context ${cluster_context} \
        --create-namespace \
        --version ${CERT_MANAGER_VERSION} \
        -f $DIR/cert-manager-helm-values.yaml

    kubectl --context ${cluster_context} \
        -n cert-manager wait deploy/cert-manager --for condition=Available=True --timeout=90s
    kubectl --context ${cluster_context} \
        -n cert-manager wait deploy/cert-manager-cainjector --for condition=Available=True --timeout=90s
    kubectl --context ${cluster_context} \
        -n cert-manager wait deploy/cert-manager-webhook --for condition=Available=True --timeout=90s
}

if [[ -z "$1" ]]; then
    error_exit "Cluster context required!"
fi

# Validation
if [[ -z "${CERT_MANAGER_VERSION}" ]]; then
    error_exit "Cert Manager helm version is not, \$CERT_MANAGER_VERSION must be defined"
fi

install_cert_manager $1