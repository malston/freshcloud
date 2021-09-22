#!/usr/bin/env bash
#
# Install Harbor

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit; pwd)"

die() {
    2>&1 echo "$@"
    exit 1
}

# shellcheck disable=SC1091
source "${__DIR}/../.env_development.sh" || die "Could not find '.env_development.sh' in root directory"
# shellcheck disable=SC1091
source "${__DIR}/../components/kubernetes-support/kubectl-support.sh" || die "Could not find 'kubectl-support.sh' in ${__DIR}/../components/kubernetes-support directory"


function create_harbor_values() {
  create_namespace harbor

  cat <<EOF > harbor-values.yaml
harborAdminPassword: $PASSWD

service:
  type: ClusterIP
  tls:
    enabled: true
    existingSecret: harbor-tls-prod
    notaryExistingSecret: notary-tls-prod

ingress:
  enabled: true
  hosts:
    core: registry.$DOMAIN
    notary: notary.$DOMAIN
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod     # use letsencrypt-prod as the cluster issuer for TLS certs
    ingress.kubernetes.io/force-ssl-redirect: "true"     # force https, even if http is requested
    kubernetes.io/ingress.class: contour                 # using Contour for ingress
    kubernetes.io/tls-acme: "true"                       # using ACME certificates for TLS
externalURL: https://registry.$DOMAIN

portal:
  tls:
    existingSecret: harbor-tls-prod
EOF
}

function helm_install_harbor() {

  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm repo update

  helm upgrade -i harbor bitnami/harbor -f harbor-values.yaml -n harbor --version 9.4.4
  rm -f harbor-values.yaml
}

function create_harbor_repos() {

   for REPO in {concourse-images,kpack}; do

     echo "Creating: ${REPO} in Harbor."

     curl --user "admin:${PASSWD}" -X POST \
         https://registry.${DOMAIN}/api/v2.0/projects \
         -H "Content-type: application/json" --data \
         '{ "project_name": "'${REPO}'",
          "metadata": {
          "auto_scan": "true",
          "enable_content_trust": "false",
          "prevent_vul": "false",
          "public": "true",
          "reuse_sys_cve_whitelist": "true",
          "severity": "high" }
          }'

    done

}

create_harbor_values
helm_install_harbor
wait_for_ready harbor
echo "Sleeping while Harbor auth is setup."
sleep 120
create_harbor_repos

cat << EOF
url: https://registry.$DOMAIN
username: admin
password: ${PASSWD}
EOF
