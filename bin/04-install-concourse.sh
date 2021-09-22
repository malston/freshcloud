#!/usr/bin/env bash
#
# Install Concourse

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit; pwd)"

die() {
    2>&1 echo "$@"
    exit 1
}

# shellcheck disable=SC1091
source "${__DIR}/../.env_development.sh" || die "Could not find '.env_development.sh' in root directory"
# shellcheck disable=SC1091
source "${__DIR}/../components/kubernetes-support/kubectl-support.sh" || die "Could not find 'kubectl-support.sh' in ${__DIR}/../components/kubernetes-support directory"


function create_concourse_values() {
  cat <<EOF > concourse-values.yaml
concourse:
  web:
    externalUrl: https://ci.$DOMAIN
    auth:
      mainTeam:
        localUser: "admin"
secrets:
  localUsers: "admin:$PASSWD"
web:
  env:
  ingress:
    enabled: true
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      kubernetes.io/ingress.class: contour
      ingress.kubernetes.io/force-ssl-redirect: "true"
      projectcontour.io/websocket-routes: "/"
      kubernetes.io/tls-acme: "true"
    hosts:
      - ci.$DOMAIN
    tls:
      - hosts:
          - ci.$DOMAIN
        secretName: concourse-cert
    hosts:
      - ci.$DOMAIN
EOF
}

function helm_install_concourse() {
  helm repo add concourse https://concourse-charts.storage.googleapis.com/
  create_namespace concourse
  helm upgrade -i concourse concourse/concourse -f concourse-values.yaml -n concourse --version 16.0.0
  rm -f concourse-values.yaml
}

create_concourse_values
helm_install_concourse
wait_for_ready concourse

cat << EOF
url: https://ci.$DOMAIN
username: admin
password: $PASSWD
EOF
