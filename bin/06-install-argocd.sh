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

function create_k8s_resources() {
    create_namespace "argocd"
    mkdir -p "${__DIR}/build/k8s/argocd"
    cat > "${__DIR}/build/k8s/argocd/resources.yaml" <<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd
  namespace: argocd
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: argocd
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: argocd
  namespace: argocd
EOF
    kubectl apply -f "${__DIR}/build/k8s/argocd/resources.yaml"
}

# shellcheck disable=SC2120
function helm_install_argocd() {
    cat > "${__DIR}/build/k8s/argocd/values.yaml" <<EOF
---
configs:
  secret:
    # Argo expects the password in the secret to be bcrypt hashed. You can create this hash with
    #
    argocdServerAdminPassword: $(htpasswd -nbBC 10 "" "$PASSWD" | tr -d ':\n' | sed "s/$2y/$2a/")
installCRDs: false
server:
  certificate:
    enabled: true
    domain: argocd.$DOMAIN
    issuer:
      name: letsencrypt-prod
      kind: ClusterIssuer
EOF
    cat > "${__DIR}/build/k8s/argocd/httpproxy.yaml" <<EOF
---
apiVersion: projectcontour.io/v1
kind: HTTPProxy
metadata:
  name: argocd
  namespace: argocd
spec:
  virtualhost:
    fqdn: argocd.$DOMAIN
    tls:
      passthrough: true
  tcpproxy:
    services:
      - name: argocd-server
        port: 443
EOF
    helm repo add argo https://argoproj.github.io/argo-helm
    helm upgrade --install argocd argo/argo-cd -f "${__DIR}/build/k8s/argocd/values.yaml" \
        --namespace argocd \
        --version "3.21.0"
    kubectl apply -f "${__DIR}/build/k8s/argocd/httpproxy.yaml"
}

function main() {
    create_k8s_resources
    helm_install_argocd
    wait_for_ready argocd
    printf "Access the ArgoCD UI at: https://%s\n" "$(kubectl get httpproxy argocd -o jsonpath='{.spec.virtualhost.fqdn}')"
    printf "User: %s\n" "admin"
    printf "Password: %s" "$PASSWD"
}

main