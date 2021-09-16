#!/usr/bin/env bash
#
# Create a k8s cluster in TKG for vSphere
# See https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/1.3/vmware-tanzu-kubernetes-grid-13/GUID-tanzu-k8s-clusters-connect-vsphere7.html

# shellcheck disable=SC1091
source ../../.env_development.sh

function tanzu_vsphere_create_k8s_cluster() {
  local temp_dir="${1:-/tmp}"
  local cluster_name="${2:-freshcloud}"
  local control_plane_ip="${3:-192.168.11.129}"
  local storage_class="${4:-kubernetes-storage-policy}"
  local kubernetes_version="${5:-1.20.7}"
  local tkg_version="${6:-1-tkg.1.7fb9067}"
  cat > "$temp_dir/cluster.yaml" <<EOF
CLUSTER_NAME: $cluster_name
CLUSTER_PLAN: dev
NAMESPACE: development
CNI: antrea
IDENTITY_MANAGEMENT_TYPE: oidc
VSPHERE_NETWORK: VM Network
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
KUBERNETES_VERSION: "v$kubernetes_version+vmware.$tkg_version"
SERVICE_DOMAIN: cluster.local
DEFAULT_STORAGE_CLASS: $storage_class
CONTROL_PLANE_VM_CLASS: best-effort-small
CONTROL_PLANE_MACHINE_COUNT: 1
CONTROL_PLANE_STORAGE_CLASS: $storage_class
WORKER_VM_CLASS: best-effort-large
WORKER_MACHINE_COUNT: 7
WORKER_STORAGE_CLASS: $storage_class
STORAGE_CLASSES: $storage_class
EOF
  tanzu cluster create "$cluster_name" --dry-run > "$temp_dir/cluster.yaml"
  printf "Workload cluster file saved to: %s\n" "$temp_dir/cluster.yaml"
  tanzu cluster create "$cluster_name" --file "$temp_dir/cluster.yaml" --tkr="v$kubernetes_version---vmware.$tkg_version" --log-file "$cluster_name.log" -v9 &
  printf "Follow logs: %s\n" "$cluster_name.log"
}

function tanzu_vsphere_delete_k8s_cluster() {
  local cluster_name=${1:-freshcloud}
  tanzu cluster delete "$cluster_name"
}

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  printf "Please set the following environment variables in .env_development.sh under root directory:\n"
  printf "AWS_ACCESS_KEY_ID\n"
  printf "AWS_SECRET_ACCESS_KEY\n"
  exit 1
fi

temp_dir=$(mktemp -d -t cluster-XXXXXXXXXX)

if [ "$1" == 'delete' ]; then
    tanzu_vsphere_delete_k8s_cluster "$2"
else
  tanzu_vsphere_create_k8s_cluster "$temp_dir" "$@"
fi
