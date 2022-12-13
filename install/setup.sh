#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

debug() {
    if [[ "$_DEBUG" = true ]]; then
        echo "$1"
    fi
}

is_vault_enabled=${ENABLE_VAULT_INTEGRATION:-false}

curl -sL https://run.solo.io/meshctl/install | GLOO_MESH_VERSION=${GLOO_PLATFORM_VERSION} sh -

export PATH=$HOME/.gloo-mesh/bin:$PATH

# Integrations
$DIR/integrations/vault/setup.sh $MGMT_CONTEXT
$DIR/integrations/cert-manager/setup.sh $MGMT_CONTEXT
$DIR/integrations/cert-manager/setup.sh $WEST_CONTEXT
$DIR/integrations/cert-manager/setup.sh $EAST_CONTEXT

# Deploy Gloo Mesh mgmt plane
$DIR/core/setup-mgmt.sh $is_vault_enabled

if [[ "${is_vault_enabled}" == true ]]; then
    $DIR/core/security/vault-pki/bootstrap-relay-pki-gen.sh
    $DIR/core/security/vault-pki/bootstrap-istio-pki-gen.sh root

    # This is later needed by RTP
    export VAULT_LB=$(kubectl --context ${MGMT_CONTEXT} get svc -n vault vault \
      -o jsonpath='{.status.loadBalancer.ingress[0].*}')
    export VAULT_ADDR="http://${VAULT_LB}:8200"
else
    debug "Generating the relay auth token and tls certs for worker clusters"
    relay_dir=$(mktemp -d)/relay-certs
    mkdir -p $relay_dir

    kubectl --context ${MGMT_CONTEXT} get secret relay-root-tls-secret -n gloo-mesh -o jsonpath='{.data.ca\.crt}' | base64 -d > $relay_dir/ca.crt
    kubectl --context ${MGMT_CONTEXT} get secret relay-identity-token-secret -n gloo-mesh -o jsonpath='{.data.token}' | base64 -d > $relay_dir/token

    kubectl --context ${EAST_CONTEXT} create ns gloo-mesh
    kubectl --context ${EAST_CONTEXT} create secret generic relay-root-tls-secret -n gloo-mesh --from-file ca.crt=$relay_dir/ca.crt
    kubectl --context ${EAST_CONTEXT} create secret generic relay-identity-token-secret -n gloo-mesh --from-file token=$relay_dir/token

    kubectl --context ${WEST_CONTEXT} create ns gloo-mesh
    kubectl --context ${WEST_CONTEXT} create secret generic relay-root-tls-secret -n gloo-mesh --from-file ca.crt=$relay_dir/ca.crt
    kubectl --context ${WEST_CONTEXT} create secret generic relay-identity-token-secret -n gloo-mesh --from-file token=$relay_dir/token

    rm -rf $relay_dir
fi

debug "Registering workload cluster $WEST_CLUSTER"
kubectl --context ${MGMT_CONTEXT} apply -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: KubernetesCluster
metadata:
  name: ${WEST_CLUSTER}
  namespace: gloo-mesh
spec:
  clusterDomain: cluster.local
EOF

debug "Registering workload cluster $EAST_CLUSTER"
kubectl --context ${MGMT_CONTEXT} apply -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: KubernetesCluster
metadata:
  name: ${EAST_CLUSTER}
  namespace: gloo-mesh
spec:
  clusterDomain: cluster.local
EOF

# Check whether to use ClusterIP or LB address
kubectl --context ${MGMT_CONTEXT} -n gloo-mesh get svc gloo-mesh-mgmt-server -o jsonpath='{.spec.type}' | grep -i LoadBalancer &> /dev/null
is_mesh_lb_enabled=$?
export GLOO_PLATFORM_RELAY_ENDPOINT=$(kubectl --context ${MGMT_CONTEXT} -n gloo-mesh get svc gloo-mesh-mgmt-server -o jsonpath='{.spec.clusterIP}'):9900
if [ $is_mesh_lb_enabled -eq 0 ]; then
    export GLOO_PLATFORM_RELAY_ENDPOINT=$(kubectl --context ${MGMT_CONTEXT} -n gloo-mesh get svc gloo-mesh-mgmt-server -o jsonpath='{.status.loadBalancer.ingress[0].*}'):9900
fi
debug "Found relay server endpoint $GLOO_PLATFORM_RELAY_ENDPOINT"

# Deploy Gloo Mesh agent + Istio (West)
$DIR/core/setup-worker.sh $WEST_CONTEXT $WEST_CLUSTER $ENABLE_VAULT
if [[ "${is_vault_enabled}" == true ]]; then
    $DIR/core/security/vault-pki/bootstrap-istio-pki-gen.sh west
    sleep 5
    debug "Enabling federation and trust on $WEST_CLUSTER using Vault"
    envsubst < <(cat $DIR/core/security/federation/federated-west-trust-policy.yaml) | kubectl --context ${WEST_CONTEXT} apply -f -
    sleep 5
    $DIR/core/restart-istio-services.sh $WEST_CONTEXT $WEST_CLUSTER
fi
kubectl --context ${WEST_CONTEXT} apply -f $DIR/core/security/strict-mtls.yaml

# Deploy Gloo Mesh agent + Istio (East)
$DIR/core/setup-worker.sh $EAST_CONTEXT $EAST_CLUSTER $ENABLE_VAULT
if [[ "${is_vault_enabled}" == true ]]; then
    $DIR/core/security/vault-pki/bootstrap-istio-pki-gen.sh east
    sleep 5
    debug "Enabling federation and trust on $EAST_CLUSTER using Vault"
    envsubst < <(cat $DIR/core/security/federation/federated-east-trust-policy.yaml) | kubectl --context ${EAST_CONTEXT} apply -f -
    sleep 5
    $DIR/core/restart-istio-services.sh $EAST_CONTEXT $EAST_CLUSTER
fi
kubectl --context ${EAST_CONTEXT} apply -f $DIR/core/security/strict-mtls.yaml

# Enable global federation
if [[ "${is_vault_enabled}" == false ]]; then
  debug "Enabling global federation"
  kubectl --context ${MGMT_CONTEXT} apply -f $DIR/core/security/federation/federated-trust-policy.yaml
fi

# Deploy Online Boutique
$DIR/apps/online-boutique/setup.sh