# Instructions

To install this project in GKE set the following environment variables

```
export PROJECT="zta-demo"
export CLUSTER_OWNER="kasunt"
export GKE_CLUSTER_REGION=australia-southeast2

export EAST_CLUSTER_PROJECT=${PROJECT}-east-cluster
export WEST_CLUSTER_PROJECT=${PROJECT}-west-cluster
export MGMT_CLUSTER_PROJECT=${PROJECT}-mgmt-cluster

export EAST_CONTEXT="gke_$(gcloud config get-value project)_${GKE_CLUSTER_REGION}_${CLUSTER_OWNER}-${EAST_CLUSTER_PROJECT}"
export WEST_CONTEXT="gke_$(gcloud config get-value project)_${GKE_CLUSTER_REGION}_${CLUSTER_OWNER}-${WEST_CLUSTER_PROJECT}"
export MGMT_CONTEXT="gke_$(gcloud config get-value project)_${GKE_CLUSTER_REGION}_${CLUSTER_OWNER}-${MGMT_CLUSTER_PROJECT}"

export MGMT_CLUSTER=mgmt-cluster
export WEST_CLUSTER=west-cluster
export EAST_CLUSTER=east-cluster

# Gloo Platform
export GLOO_PLATFORM_VERSION=2.1.2
export GLOO_PLATFORM_HELM_VERSION=v${GLOO_PLATFORM_VERSION}

# Istio
export ISTIO_IMAGE_REPO=us-docker.pkg.dev/gloo-mesh/istio-1cf99a48c9d8
export ISTIO_IMAGE_TAG=1.15.3-solo
export ISTIO_VERSION=1.15.3
export ISTIO_HELM_VERSION=${ISTIO_VERSION}
export ISTIO_REVISION=1-15-3

# Integration services
export CERT_MANAGER_VERSION=v1.10.1
export VAULT_VERSION=0.22.1
```

And then run the provision script

```
./provision-gke-cluster.sh create -n $EAST_CLUSTER_PROJECT -o $CLUSTER_OWNER -a 1 -r $GKE_CLUSTER_REGION
./provision-gke-cluster.sh create -n $WEST_CLUSTER_PROJECT -o $CLUSTER_OWNER -a 1 -r $GKE_CLUSTER_REGION
./provision-gke-cluster.sh create -n $MGMT_CLUSTER_PROJECT -o $CLUSTER_OWNER -a 1 -r $GKE_CLUSTER_REGION
```