#!/usr/bin/env bash
#
# Create a k8s cluster in TKG for vSphere
# See https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/1.3/vmware-tanzu-kubernetes-grid-13/GUID-tanzu-k8s-clusters-connect-vsphere7.html

# shellcheck disable=SC1091
__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit; pwd)"
source "$__DIR/../../../.env_development.sh"

function die() {
    2>&1 echo "$@"
    exit 1
}

function tanzu_vsphere_create_k8s_cluster() {
  local temp_dir="${1:-/tmp}"
  local cluster_name="${2:-$K8S_CLUSTER_NAME}"
  local namespace="${3:-ns1}"
  local control_plane_ip="${4:-$CONTROL_PLANE_IP}"
  local network="${5:-"VM Network"}"
  local storage_class="${6:-pacific-gold-storage-policy}"
  local kubernetes_version="${7:-v1.20.9}"
  local tkg_version="${8:-1-tkg.1.a4cee5b}"
  cat > "$temp_dir/cluster-config.yaml" <<EOF
CLUSTER_NAME: $cluster_name
CLUSTER_PLAN: dev
NAMESPACE: $namespace
CNI: antrea
IDENTITY_MANAGEMENT_TYPE: oidc
VSPHERE_NETWORK: $network
VSPHERE_SSH_AUTHORIZED_KEY:
VSPHERE_USERNAME:
VSPHERE_PASSWORD:
VSPHERE_SERVER:
VSPHERE_DATACENTER:
VSPHERE_RESOURCE_POOL:
VSPHERE_DATASTORE:
VSPHERE_FOLDER:
VSPHERE_TLS_THUMBPRINT:
VSPHERE_INSECURE: true
VSPHERE_CONTROL_PLANE_ENDPOINT: $control_plane_ip
ENABLE_MHC: true
MHC_UNKNOWN_STATUS_TIMEOUT: 5m
MHC_FALSE_STATUS_TIMEOUT: 12m
ENABLE_AUDIT_LOGGING: true
ENABLE_DEFAULT_STORAGE_CLASS: true
CLUSTER_CIDR: 100.96.0.0/11
SERVICE_CIDR: 100.64.0.0/13
ENABLE_AUTOSCALER: false
KUBERNETES_VERSION: "$kubernetes_version+vmware.$tkg_version"
SERVICE_DOMAIN: cluster.local
DEFAULT_STORAGE_CLASS: $storage_class
CONTROL_PLANE_VM_CLASS: best-effort-small
CONTROL_PLANE_MACHINE_COUNT: 1
CONTROL_PLANE_STORAGE_CLASS: $storage_class
WORKER_VM_CLASS: best-effort-large
WORKER_MACHINE_COUNT: 3
WORKER_STORAGE_CLASS: $storage_class
STORAGE_CLASSES: $storage_class
EOF
  tanzu cluster create "$cluster_name" --file "$temp_dir/cluster-config.yaml" --tkr="$kubernetes_version---vmware.$tkg_version" --dry-run > "$temp_dir/cluster.yaml"
  printf "Workload cluster:\n"
  printf "%s tanzu cluster config saved to: %s\n" "*" "$temp_dir/cluster-config.yaml"
  printf "%s k8s cluster manifest saved to: %s\n" "*" "$temp_dir/cluster.yaml"
  printf "%s cli logs saved to: %s\n" "*" "$temp_dir/$cluster_name.log"
  echo y | tanzu cluster create "$cluster_name" --file "$temp_dir/cluster-config.yaml" --tkr="$kubernetes_version---vmware.$tkg_version" --log-file "$temp_dir/$cluster_name.log" -v9
}

function tanzu_vsphere_delete_k8s_cluster() {
  local cluster_name=${1:-dev}
  tanzu cluster delete "$cluster_name"
}

function tanzu_login() {
  local supervisor_cluster=${1}
  tanzu login --kubeconfig "$HOME/.kube/config" --context "$supervisor_cluster" --name "$supervisor_cluster" &> /dev/null
}

if [ -z "$MANAGEMENT_CLUSTER_NAME" ]; then
  printf "Please set the following environment variables in .env_development.sh under root directory:\n"
  printf "MANAGEMENT_CLUSTER_NAME\n"
  exit 1
fi

tanzu_login "$MANAGEMENT_CLUSTER_NAME"

temp_dir=$(mktemp -d -t cluster-XXXXXXXXXX)

if [ "$1" == 'delete' ]; then
    tanzu_vsphere_delete_k8s_cluster "$2"
else
  tanzu_vsphere_create_k8s_cluster "$temp_dir" "$@"
fi
