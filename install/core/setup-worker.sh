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

install_istio() {
    local cluster_context=$1
    local cluster_name=$2
    local vault_enabled=$3

    print_operation_info "Installing Istio on ${cluster_name} cluster"

    helm repo add istio https://istio-release.storage.googleapis.com/charts
    helm repo update

    kubectl --context ${cluster_context} create ns istio-config

    debug "Installing Istio base on worker clusters ...."
    envsubst < <(cat $DIR/istio/base-helm-values.yaml) | helm --kube-context ${cluster_context} upgrade --install istio-base istio/base \
        -n istio-system \
        --version $ISTIO_HELM_VERSION \
        --create-namespace -f -

    debug "Installing Istio control plane on worker clusters ...."
    if [[ "${vault_enabled}" == true ]]; then
        envsubst < <(cat $DIR/istio/istiod-helm-values.yaml) | helm --kube-context ${cluster_context} upgrade --install istiod istio/istiod \
            -n istio-system \
            --version $ISTIO_HELM_VERSION \
            --post-renderer $DIR/istio/kustomize/istiod/kustomize \
            -f -
    else
        envsubst < <(cat $DIR/istio/istiod-helm-values.yaml) | helm --kube-context ${cluster_context} upgrade --install istiod istio/istiod \
            -n istio-system \
            --version $ISTIO_HELM_VERSION \
            --create-namespace -f -
    fi

    debug "Installing Istio ingress gateways on worker clusters ...."
    envsubst < <(cat $DIR/istio/ingress-gateway-helm-values.yaml) | helm --kube-context ${cluster_context} upgrade --install istio-ingressgateway istio/gateway \
        -n istio-ingress \
        --version $ISTIO_HELM_VERSION \
        --post-renderer $DIR/istio/kustomize/gateways/kustomize \
        --create-namespace -f -

    debug "Installing Istio east/west gateways on worker clusters ...."
    envsubst < <(cat $DIR/istio/eastwest-gateway-helm-values.yaml) | helm --kube-context ${cluster_context} upgrade --install istio-eastwestgateway istio/gateway \
        -n istio-eastwest \
        --version $ISTIO_HELM_VERSION \
        --post-renderer $DIR/istio/kustomize/gateways/kustomize \
        --create-namespace -f -
}

install_gloo_platform_agent() {
    local cluster_context=$1
    local cluster_name=$2

    print_operation_info "Installing Gloo Platform agent on ${cluster_name} cluster"

    helm repo add gloo-mesh-agent https://storage.googleapis.com/gloo-mesh-enterprise/gloo-mesh-agent
    helm repo update
    helm pull gloo-mesh-agent/gloo-mesh-agent --version $GLOO_PLATFORM_HELM_VERSION --untar
    kubectl --context ${cluster_context} apply -f gloo-mesh-agent/charts/gloo-mesh-crds/crds
    rm -rf gloo-mesh-agent

    helm upgrade --install gloo-mesh-agent gloo-mesh-agent/gloo-mesh-agent \
        --kube-context=${cluster_context} \
        --namespace gloo-mesh \
        --version $GLOO_PLATFORM_HELM_VERSION \
        --set cluster="${cluster_name}" \
        --set relay.serverAddress="${GLOO_PLATFORM_RELAY_ENDPOINT}" \
        --create-namespace \
        -f $DIR/gloo-mesh/gloo-mesh-agent-2.1.yaml

    kubectl --context ${cluster_context} \
        -n gloo-mesh wait deploy/gloo-mesh-agent --for condition=Available=True --timeout=90s
}

install_gloo_platform_addons() {
    local cluster_context=$1
    local cluster_name=$2

    print_operation_info "Installing Gloo Platform addons on ${cluster_name} cluster"

    kubectl --context ${cluster_context} create namespace gloo-mesh-addons
    kubectl --context ${cluster_context} label namespace gloo-mesh-addons istio.io/rev=$ISTIO_REVISION

    helm repo add gloo-mesh-agent https://storage.googleapis.com/gloo-mesh-enterprise/gloo-mesh-agent
    helm repo update

    helm upgrade --install gloo-mesh-agent-addons gloo-mesh-agent/gloo-mesh-agent \
        --kube-context=${cluster_context} \
        --namespace gloo-mesh-addons \
        --version $GLOO_PLATFORM_HELM_VERSION \
        --set glooMeshAgent.enabled=false \
        --set rate-limiter.enabled=true \
        --set ext-auth-service.enabled=true
}

if [[ -z "$1" ]]; then
    error_exit "Cluster context required!"
fi
if [[ -z "$2" ]]; then
    error_exit "Cluster name required!"
fi

# Validation
if [[ -z "${GLOO_PLATFORM_HELM_VERSION}" ]]; then
    error_exit "Gloo Platform helm version is not, \$GLOO_PLATFORM_HELM_VERSION must be defined"
fi
if [[ -z "${GLOO_PLATFORM_RELAY_ENDPOINT}" ]]; then
    error_exit "Gloo Platform relay endpoint is not defined, \$GLOO_PLATFORM_RELAY_ENDPOINT must be defined"
fi
if [[ -z "${ISTIO_HELM_VERSION}" ]]; then
    error_exit "Istio helm version is not set, \$ISTIO_HELM_VERSION must be set"
fi 
if [[ -z "${ISTIO_REVISION}" ]]; then
    error_exit "Istio revision is not set, \$ISTIO_REVISION must be defined"
fi

# For setting up Istio
export CLUSTER_NAME="${2}"
export ISTIO_TRUST_DOMAIN="${2}.solo.io"
export ISTIO_NETWORK="${2}-network"

is_vault_enabled=${3:-false}

install_gloo_platform_agent $1 $2

install_istio $1 $2 "$is_vault_enabled"

install_gloo_platform_addons $1 $2