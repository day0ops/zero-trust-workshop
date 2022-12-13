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

check_vault_status() {
    vault status &> /dev/null
    while [[ $? -ne 0 ]]; do !!; sleep 5; done
}

generate_root() {
    print_operation_info "Bootstrapping the Istio PKI on Vault"

    check_vault_status

    local cert_gen_dir=$(mktemp -d)/certs/istio
    mkdir -p $cert_gen_dir

    # Generate offline root CA (10 year expiry)
    cfssl genkey \
      -initca $DIR/istio/root-template.json | cfssljson -bare $cert_gen_dir/root-cert

    cat $cert_gen_dir/root-cert-key.pem $cert_gen_dir/root-cert.pem > $cert_gen_dir/root-bundle.pem

    # Enable PKI engine
    vault secrets enable pki

    # Import Root CA
    vault write -format=json pki/config/ca pem_bundle=@$cert_gen_dir/root-bundle.pem

    rm -rf $cert_gen_dir
}

generate_int_west_cluster() {
    print_operation_info "Bootstrapping the intermediate Istio PKI for $WEST_CLUSTER cluster on Vault"

    # Enable PKI for west mesh (intermediate signing)
    vault secrets enable -path=istio-west-mesh-pki-int pki

    # Tune with 3 years TTL
    vault secrets tune -max-lease-ttl="26280h" istio-west-mesh-pki-int

    vault policy write gen-int-ca-istio-west-mesh - <<EOF
path "istio-west-mesh-pki-int/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "pki/cert/ca" {
  capabilities = ["read"]
}
path "pki/root/sign-intermediate" {
  capabilities = ["create", "read", "update", "list"]
}
EOF

    # Enable Kubernetes authentication
    vault auth enable -path=kube-west-mesh-auth kubernetes

    local vault_sa_name=$(kubectl --context $WEST_CONTEXT get sa istiod-$ISTIO_REVISION -n istio-system \
      -o jsonpath="{.secrets[*]['name']}")
    local sa_token=$(kubectl --context $WEST_CONTEXT get secret $vault_sa_name -n istio-system \
      -o 'go-template={{ .data.token }}' | base64 --decode)
    local sa_ca_crt=$(kubectl config view --raw -o json \
      | jq -r --arg wc $WEST_CONTEXT '. as $c | $c.contexts[] | select(.name == $wc) as $context | $c.clusters[] | select(.name == $context.context.cluster) | .cluster."certificate-authority-data"' \
      | base64 -d) 
    local k8s_addr=$(kubectl config view -o json \
      | jq -r --arg wc $WEST_CONTEXT '. as $c | $c.contexts[] | select(.name == $wc) as $context | $c.clusters[] | select(.name == $context.context.cluster) | .cluster.server')

    # Set Kubernetes auth config for Vault to the mounted token
    vault write auth/kube-west-mesh-auth/config \
      token_reviewer_jwt="$sa_token" \
      kubernetes_host="$k8s_addr" \
      kubernetes_ca_cert="$sa_ca_crt" \
      issuer="https://kubernetes.default.svc.cluster.local"

    # Bind the istiod service account to the PKI policy
    vault write \
      auth/kube-west-mesh-auth/role/gen-int-ca-istio-west-mesh \
      bound_service_account_names=istiod-$ISTIO_REVISION \
      bound_service_account_namespaces=istio-system \
      policies=gen-int-ca-istio-west-mesh \
      ttl=720h
}

generate_int_east_cluster() {
    print_operation_info "Bootstrapping the intermediate Istio PKI for $EAST_CLUSTER cluster on Vault"

    # Enable PKI for east mesh (intermediate signing)
    vault secrets enable -path=istio-east-mesh-pki-int pki

    # Tune with 3 years TTL
    vault secrets tune -max-lease-ttl="26280h" istio-east-mesh-pki-int

    # Policy for intermediate signing
    vault policy write gen-int-ca-istio-east-mesh - <<EOF
path "istio-east-mesh-pki-int/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "pki/cert/ca" {
  capabilities = ["read"]
}
path "pki/root/sign-intermediate" {
  capabilities = ["create", "read", "update", "list"]
}
EOF

    # Enable Kubernetes authentication
    vault auth enable -path=kube-east-mesh-auth kubernetes

    # Policy for intermediate signing
    local vault_sa_name=$(kubectl --context $EAST_CONTEXT get sa istiod-$ISTIO_REVISION -n istio-system \
      -o jsonpath="{.secrets[*]['name']}")
    local sa_token=$(kubectl --context $EAST_CONTEXT get secret $vault_sa_name -n istio-system \
      -o 'go-template={{ .data.token }}' | base64 --decode)
    local sa_ca_crt=$(kubectl config view --raw -o json \
      | jq -r --arg wc $EAST_CONTEXT '. as $c | $c.contexts[] | select(.name == $wc) as $context | $c.clusters[] | select(.name == $context.context.cluster) | .cluster."certificate-authority-data"' \
      | base64 -d) 
    local k8s_addr=$(kubectl config view -o json \
      | jq -r --arg wc $EAST_CONTEXT '. as $c | $c.contexts[] | select(.name == $wc) as $context | $c.clusters[] | select(.name == $context.context.cluster) | .cluster.server')

    # Set Kubernetes auth config for Vault to the mounted token
    vault write auth/kube-east-mesh-auth/config \
      token_reviewer_jwt="$sa_token" \
      kubernetes_host="$k8s_addr" \
      kubernetes_ca_cert="$sa_ca_crt" \
      issuer="https://kubernetes.default.svc.cluster.local"

    # Bind the istiod service account to the PKI policy
    vault write \
      auth/kube-east-mesh-auth/role/gen-int-ca-istio-east-mesh \
      bound_service_account_names=istiod-$ISTIO_REVISION \
      bound_service_account_namespaces=istio-system \
      policies=gen-int-ca-istio-east-mesh \
      ttl=720h
}

# Find the public IP for the vault service
export VAULT_LB=$(kubectl --context ${MGMT_CONTEXT} get svc -n vault vault \
    -o jsonpath='{.status.loadBalancer.ingress[0].*}')
export VAULT_ADDR="http://${VAULT_LB}:8200"
export VAULT_TOKEN="root"

if [[ -z "${VAULT_LB}" ]]; then
    error_exit "Unable to obtain the address for the Vault service"
fi

# Validation
if [[ -z "${ISTIO_REVISION}" ]]; then
    error_exit "Istio revision is not, \$ISTIO_REVISION must be defined"
fi

shift $((OPTIND-1))
subcommand=$1; shift
case "$subcommand" in
    root )
        generate_root
    ;;
    west )
        generate_int_west_cluster
    ;;
    east )
        generate_int_east_cluster
    ;;
    * ) # Invalid subcommand
        if [ ! -z $subcommand ]; then
            echo "Invalid subcommand: $subcommand"
        fi
        exit 1
    ;;
esac