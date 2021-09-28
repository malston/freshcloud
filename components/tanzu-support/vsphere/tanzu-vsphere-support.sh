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
  mkdir -p "$__DIR/build/k8s/tanzu"
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
WORKER_MACHINE_COUNT: 5
WORKER_STORAGE_CLASS: $storage_class
STORAGE_CLASSES: $storage_class
EOF
  tanzu cluster create "$cluster_name" --file "$temp_dir/cluster-config.yaml" --tkr="$kubernetes_version---vmware.$tkg_version" --dry-run > "$temp_dir/cluster.yaml"
  printf "Workload cluster:\n"
  printf "%s tanzu cluster config saved to: %s\n" "*" "$temp_dir/cluster-config.yaml"
  printf "%s k8s cluster manifest saved to: %s\n" "*" "$temp_dir/cluster.yaml"
  printf "%s cli logs saved to: %s\n" "*" "$temp_dir/$cluster_name.log"
  printf "Add ephemeral volume to workers by adding the following under topology.workers to %s." "$temp_dir/cluster.yaml"
  echo "
  volumes:
  - name: ephemeral-1
    mountPath: /var/lib
    capacity:
      storage: 50Gi
  "
  read -rp "Press return when finished." -n 1 -r
  cp "$temp_dir/cluster.yaml" "$__DIR/build/k8s/tanzu/cluster.yaml"
  kubectl apply -f "$temp_dir/cluster.yaml"
  tanzu cluster get "$cluster_name" -n "$namespace"
  echo "Try issuing the following commands to watch progress:"
  echo kubectl get tkc "$cluster_name" -n "$namespace"
  echo kubectl get machines,machinedeployment -n "$namespace"
}

function tanzu_vsphere_delete_k8s_cluster() {
  local cluster_name=${1:-dev}
  local namespace=${2:-ns1}
  tanzu cluster delete "$cluster_name" -n "$namespace"
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

if [ "$1" == 'delete' ]; then
    tanzu_vsphere_delete_k8s_cluster "$2" "$3"
else
  temp_dir=$(mktemp -d -t cluster-XXXXXXXXXX)
  tanzu_vsphere_create_k8s_cluster "$temp_dir" "$@"
  echo
  echo "Once the cluster is created be sure to login using the vsphere plugin:"
  echo "kubectl vsphere login \\"
  echo "  --server \"$MANAGEMENT_CLUSTER_NAME\" \\"
  echo "  --tanzu-kubernetes-cluster-name \"$K8S_CLUSTER_NAME\" \\"
  echo "  --tanzu-kubernetes-cluster-namespace \"$K8S_NAMESPACE\" \\"
  echo "  --vsphere-username \"administrator@vsphere.local\" \\"
  echo "  --insecure-skip-tls-verify"
fi
