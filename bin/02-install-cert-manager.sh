#!/usr/bin/env bash
#
# Install Cert-Manager

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit; pwd)"

die() {
    2>&1 echo "$@"
    exit 1
}

# shellcheck disable=SC1091
source "${__DIR}/../.env_development.sh" || die "Could not find '.env_development.sh' in root directory"
# shellcheck disable=SC1091
source "${__DIR}/../components/kubernetes-support/kubectl-support.sh" || die "Could not find 'kubectl-support.sh' in ${__DIR}/../components/kubernetes-support directory"

function helm_install_cert_manager() {
    create_namespace "cert-manager"
    helm repo add "jetstack" https://charts.jetstack.io
    helm repo update
    helm upgrade -i "cert-manager" "jetstack/cert-manager" \
      --namespace "cert-manager" \
      --version "v1.3.1" \
      --set installCRDs="true" || die "Failed to install cert-manager."
}

function install_cluster_issuer() {
    if [ "$CHALLENGE_TYPE" == 'dns' ]; then
        kubectl create secret generic route53-secret \
          --from-literal=secret-access-key="$AWS_SECRET_ACCESS_KEY" \
          --namespace cert-manager
    fi
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: mjoey@vmware.com
    preferredChain: ""
    privateKeySecretRef:
      name: letsencrypt-prod
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
    - http01:
        ingress:
          class: contour$(
if [ "$CHALLENGE_TYPE" == 'dns' ]; then
  echo "
    - dns01:
        cnameStrategy: Follow
        route53:
          accessKeyID: $AWS_ACCESS_KEY_ID
          hostedZoneID: $ZONE_ID
          region: us-east-1
          secretAccessKeySecretRef:
            key: secret-access-key
            name: route53-secret
      selector:
        dnsZones:
        - $DOMAIN"
fi)
EOF
}

helm_install_cert_manager
wait_for_ready "cert-manager"
sleep 10;
install_cluster_issuer
