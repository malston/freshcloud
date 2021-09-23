#!/usr/bin/env bash
#
# Install Contour

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit; pwd)"

die() {
    2>&1 echo "$@"
    exit 1
}

# shellcheck disable=SC1091
source "${__DIR}/../.env_development.sh" || die "Could not find '.env_development.sh' in root directory"
# shellcheck disable=SC1091
source "${__DIR}/../components/kubernetes-support/kubectl-support.sh" || die "Could not find 'kubectl-support.sh' in ${__DIR}/../components/kubernetes-support directory"

function configure_psps() {
    # allows the deployment of privileged workloads in default namespace
    kubectl create rolebinding rolebinding-default-privileged-sa-ns_default \
      --clusterrole=psp:vmware-system-privileged \
      --group=system:serviceaccounts \
      --namespace=default
    # grants system:serviceaccounts cluster-wide access to run a privileged workloads
    kubectl create clusterrolebinding clusterrolebinding-privileged-sa \
      --clusterrole=psp:vmware-system-privileged \
      --group=system:serviceaccounts
    # grants system:serviceaccounts cluster-wide access to run a restricted set of workloads
    kubectl create rolebinding psp:serviceaccounts \
      --clusterrole=psp:vmware-system-restricted \
      --group=system:serviceaccounts
}

function helm_install_contour() {
    create_namespace "projectcontour"
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update
    helm upgrade -i ingress bitnami/contour -n "projectcontour"  --version 3.3.1 || die "Failed to install Contour."
}

function get_load_balancer_ip() {
  echo "Waiting to get the load-balancer IP."
  while true; do
    if [ -z "$LB" ]; then
      LB=$(kubectl describe svc ingress-contour-envoy --namespace projectcontour | grep Ingress | awk '{print $3}')
      sleep 3;
    else
      echo "Create a DNS A for *.$DOMAIN to $LB"
      break
    fi
  done
}

configure_psps
helm_install_contour
get_load_balancer_ip
