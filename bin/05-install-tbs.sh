#!/usr/bin/env bash
#
# Install Tanzu Build Service

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit; pwd)"

die() {
    2>&1 echo "$@"
    exit 1
}

# shellcheck disable=SC1091
source "${__DIR}/../.env_development.sh" || die "Could not find '.env_development.sh' in root directory"
# shellcheck disable=SC1091
source "${__DIR}/../components/kubernetes-support/kubectl-support.sh" || die "Could not find 'kubectl-support.sh' in ${__DIR}/../components/kubernetes-support directory"

function login_harbor() {
    echo "Logging into ${PRIVATE_REGISTRY}"
    echo "${PASSWD}" | docker login -u admin "${PRIVATE_REGISTRY}" --password-stdin
}

function login_pivotal_registry() {
    echo "Logging into ${PIVOTAL_REGISTRY}"
    echo "${PIVOTAL_REGISTRY_PASSWORD}" | docker login "${PIVOTAL_REGISTRY}" -u "${PIVOTAL_REGISTRY_USER}" --password-stdin
}

function relocate_images() {
    echo "Relocating images from ${PIVOTAL_REGISTRY} to ${PRIVATE_REGISTRY}/tanzu"
    imgpkg copy -b "${PIVOTAL_REGISTRY}/build-service/bundle:${TANZU_BUILD_SERVICE_VERSION}" --to-repo "${PRIVATE_REGISTRY}/tanzu/build-service"
    return $?
}

function create_tanzu_project() {
  echo "Creating 'tanzu' project in ${PRIVATE_REGISTRY}"
  curl --user "admin:${PASSWD}" --silent -X POST \
      "https://${PRIVATE_REGISTRY}/api/v2.0/projects" \
      -H "Content-type: application/json" --data \
      '{ "project_name": "tanzu",
      "metadata": {
      "auto_scan": "true",
      "enable_content_trust": "false",
      "prevent_vul": "false",
      "public": "true",
      "reuse_sys_cve_whitelist": "true",
      "severity": "high" }
      }'
    return $?
}

function create_roles() {
    create_namespace "build-service"
    create_namespace "kpack"
    mkdir -p "${__DIR}/build/k8s/build-service"
    cat > "${__DIR}/build/k8s/build-service/roles.yaml" <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: build-service-install-cluster-role
rules:
  - apiGroups:
      - "admissionregistration.k8s.io"
    resources:
      - mutatingwebhookconfigurations
      - validatingwebhookconfigurations
    verbs:
      - '*'
  - apiGroups:
      - "rbac.authorization.k8s.io"
    resources:
      - clusterroles
      - clusterrolebindings
    verbs:
      - '*'
  - apiGroups:
      - "apiextensions.k8s.io"
    resources:
      - customresourcedefinitions
    verbs:
      - '*'
  - apiGroups:
      - "storage.k8s.io"
    resources:
      - storageclasses
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - kpack.io
    resources:
      - builds
      - builds/status
      - builds/finalizers
      - images
      - images/status
      - images/finalizers
      - builders
      - builders/status
      - clusterbuilders
      - clusterbuilders/status
      - clusterstores
      - clusterstores/status
      - clusterstacks
      - clusterstacks/status
      - sourceresolvers
      - sourceresolvers/status
    verbs:
      - '*'
  - apiGroups:
      - "projects.vmware.com"
    resources:
      - projects
    verbs:
      - '*'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: build-service-install-role
  namespace: build-service
rules:
  - apiGroups:
      - ""
    resources:
      - configmaps
      - secrets
      - serviceaccounts
      - services
      - namespaces
    verbs:
      - '*'
  - apiGroups:
      - "rbac.authorization.k8s.io"
    resources:
      - roles
      - rolebindings
    verbs:
      - '*'
  - apiGroups:
      - apps
    resources:
      - deployments
      - daemonsets
    verbs:
      - '*'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: kpack-install-role
  namespace: kpack
rules:
  - apiGroups:
      - ""
    resources:
      - services
      - serviceaccounts
      - namespaces
      - secrets
      - configmaps
    verbs:
      - '*'
  - apiGroups:
      - "rbac.authorization.k8s.io"
    resources:
      - roles
      - rolebindings
    verbs:
      - '*'
  - apiGroups:
      - apps
    resources:
      - deployments
      - daemonsets
    verbs:
      - '*'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: kapp-role
  namespace: kapp-controller
rules:
  - apiGroups:
      - ""
    resources:
      - configmaps
    verbs:
      - '*'
EOF
  kubectl apply -f "${__DIR}/build/k8s/build-service/roles.yaml"
}

function install_build_service() {
  create_roles
  mkdir -p /tmp/bundle
  imgpkg pull -b "${PRIVATE_REGISTRY}/tanzu/build-service:${TANZU_BUILD_SERVICE_VERSION}" -o /tmp/bundle
  ytt -f /tmp/bundle/values.yaml \
      -f /tmp/bundle/config/ \
      -v docker_repository="${PRIVATE_REGISTRY}/tanzu/build-service" \
      -v docker_username="admin" \
      -v docker_password="${PASSWD}" \
      -v tanzunet_username="${PIVOTAL_REGISTRY_USER}" \
      -v tanzunet_password="${PIVOTAL_REGISTRY_PASSWORD}" \
      | kbld -f /tmp/bundle/.imgpkg/images.yml -f- \
      | kapp deploy -a tanzu-build-service -f- -y
  kubectl -n build-service get TanzuNetDependencyUpdater dependency-updater -o yaml
}

function import_build_service_dependencies() {
  if [ ! -f "${__DIR}/build/k8s/build-service/descriptor-$TANZU_BUILD_SERVICE_DESCRIPTOR_VERSION.yaml" ]; then
    mkdir -p "${__DIR}/build/k8s/build-service"
    read -rp "Please download descriptor-$TANZU_BUILD_SERVICE_DESCRIPTOR_VERSION.yaml from https://network.pivotal.io to ${__DIR}/build/k8s/build-service. Press return when finished." -n 1 -r
    if [ ! -f "${__DIR}/build/k8s/build-service/descriptor-$TANZU_BUILD_SERVICE_DESCRIPTOR_VERSION.yaml" ]; then
      die "Could not find ${__DIR}/build/k8s/build-service/descriptor-$TANZU_BUILD_SERVICE_DESCRIPTOR_VERSION.yaml"
    fi
  fi
  kp import -f "${__DIR}/build/k8s/build-service/descriptor-$TANZU_BUILD_SERVICE_DESCRIPTOR_VERSION.yaml" --show-changes
}

function verify() {
    kp clusterbuilder list
}

function unistall_build_service() {
    kapp delete -a tanzu-build-service -n tap-install
    kubectl delete -f "${__DIR}/build/k8s/build-service/roles.yaml"
}

function main() {
  if [[ -z $PASSWD ]]; then
      echo -n "Enter password for $PRIVATE_REGISTRY: "
      read -rs PASSWD
      echo
  fi

  if ! login_harbor; then
    echo ""
    echo "Failed to login to ${PRIVATE_REGISTRY}. Please check your credentials."
    exit 1
  fi

  if [[ -z $PIVOTAL_REGISTRY_USER ]]; then
      echo -n "Enter username for $PIVOTAL_REGISTRY: "
      read -r PIVOTAL_REGISTRY_USER
      echo
  fi

  if [[ -z $PIVOTAL_REGISTRY_PASSWORD ]]; then
      echo -n "Enter password for $PIVOTAL_REGISTRY: "
      read -rs PIVOTAL_REGISTRY_PASSWORD
      echo
  fi

  if ! login_pivotal_registry; then
    echo ""
    echo "Failed to login to ${PIVOTAL_REGISTRY}. Please check your credentials."
    exit 1
  fi

  if ! create_tanzu_project; then
    echo ""
    echo "Failed to create tanzu project in ${PRIVATE_REGISTRY}."
    exit 1
  fi

  if ! relocate_images; then
    echo ""
    echo "Failed to relocate images to ${PRIVATE_REGISTRY}."
    exit 1
  fi

  install_build_service
  import_build_service_dependencies
  verify
}

PRIVATE_REGISTRY="registry.${DOMAIN}"
PIVOTAL_REGISTRY="registry.pivotal.io"
TANZU_BUILD_SERVICE_VERSION="1.2.2"
TANZU_BUILD_SERVICE_DESCRIPTOR_VERSION="100.0.158"

main "$@"