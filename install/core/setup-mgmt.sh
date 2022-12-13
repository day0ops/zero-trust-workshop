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

install_gloo_mesh() {
    local is_vault_enabled=$1

    print_operation_info "Installing Gloo Mesh management plane"

    helm repo add gloo-mesh-enterprise https://storage.googleapis.com/gloo-mesh-enterprise/gloo-mesh-enterprise 
    helm repo update
    helm pull gloo-mesh-enterprise/gloo-mesh-enterprise --version $GLOO_PLATFORM_HELM_VERSION --untar
    kubectl --context ${MGMT_CONTEXT} apply -f gloo-mesh-enterprise/charts/gloo-mesh-crds/crds
    rm -rf gloo-mesh-enterprise

    if [[ "$is_vault_enabled" == true ]]; then
        envsubst '${GLOO_PLATFORM_GATEWAY_LICENSE_KEY},${GLOO_PLATFORM_MESH_LICENSE_KEY},${MGMT_CLUSTER},${ISTIO_IMAGE_REPO},${ISTIO_IMAGE_TAG},${ISTIO_REVISION}' < <(cat $DIR/gloo-mesh/gloo-mesh-mgmt-plane-disabled-self-ca-2.1.yaml) | helm install gloo-mesh-enterprise gloo-mesh-enterprise/gloo-mesh-enterprise \
            --kube-context ${MGMT_CONTEXT} \
            --namespace gloo-mesh \
            --version ${GLOO_PLATFORM_HELM_VERSION} \
            --create-namespace \
            -f -
    else
        envsubst '${GLOO_PLATFORM_GATEWAY_LICENSE_KEY},${GLOO_PLATFORM_MESH_LICENSE_KEY},${MGMT_CLUSTER},${ISTIO_IMAGE_REPO},${ISTIO_IMAGE_TAG},${ISTIO_REVISION}' < <(cat $DIR/gloo-mesh/gloo-mesh-mgmt-plane-2.1.yaml) | helm install gloo-mesh-enterprise gloo-mesh-enterprise/gloo-mesh-enterprise \
            --kube-context ${MGMT_CONTEXT} \
            --namespace gloo-mesh \
            --version ${GLOO_PLATFORM_HELM_VERSION} \
            --create-namespace \
            -f -
    fi

    kubectl --context ${MGMT_CONTEXT} \
        -n gloo-mesh wait deploy/gloo-mesh-mgmt-server --for condition=Available=True --timeout=90s

    wait_for_lb_address $MGMT_CONTEXT "gloo-mesh-mgmt-server" "gloo-mesh"
}

# Validation
if [[ -z "${GLOO_PLATFORM_HELM_VERSION}" ]]; then
    error_exit "Gloo Platform helm version is not, \$GLOO_PLATFORM_HELM_VERSION must be defined"
fi
if [[ -z "${GLOO_PLATFORM_GATEWAY_LICENSE_KEY}" ]]; then
    error_exit "Gloo Platform license for gateway is not, \$GLOO_PLATFORM_GATEWAY_LICENSE_KEY must be defined"
fi
if [[ -z "${GLOO_PLATFORM_MESH_LICENSE_KEY}" ]]; then
    error_exit "Gloo Platform license for mesh is not, \$GLOO_PLATFORM_MESH_LICENSE_KEY must be defined"
fi

is_vault_enabled=${1:-false}

install_gloo_mesh $is_vault_enabled