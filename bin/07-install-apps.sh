#!/usr/bin/env bash
#
# Install ArgoCD Applications

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit; pwd)"

die() {
    2>&1 echo "$@"
    exit 1
}

# shellcheck disable=SC1091
source "${__DIR}/../.env_development.sh" || die "Could not find '.env_development.sh' in root directory"
# shellcheck disable=SC1091
source "${__DIR}/../components/kubernetes-support/kubectl-support.sh" || die "Could not find 'kubectl-support.sh' in ${__DIR}/../components/kubernetes-support directory"

function install_argocli() {
  if ! type argocd >/dev/null 2>&1; then
      printf "Please follow these instructions: %s\nto install the ArgoCD CLI. Make sure 'argocd' in on the PATH.\n" "https://argoproj.github.io/argo-cd/cli_installation"
      read -rp "Press return when finished." -n 1 -r
      if ! type argocd >/dev/null 2>&1; then
          die "Could not find 'argocd' on the PATH"
      fi
  fi
}

function configure_argocd() {
    login_argocd
    if ! argocd cluster list --server "argocd.$DOMAIN" >/dev/null 2>&1; then
      register_cluster
    fi
}

function login_argocd() {
    argocd login "$(kubectl get httpproxy argocd -n argocd -o jsonpath='{.spec.virtualhost.fqdn}')" --username admin --password "$PASSWD"
}

function register_cluster() {
    echo "Registering cluster with ArgoCD..."
    # Create kubeconfig context with Service Account secret
    TOKEN_SECRET=$(kubectl get serviceaccount -n argocd argocd -o jsonpath='{.secrets[0].name}')
    TOKEN=$(kubectl get secret -n argocd "$TOKEN_SECRET" -o jsonpath='{.data.token}' | base64 --decode)
    CLUSTER_NAME=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='"$K8S_CLUSTER_NAME"')].context.cluster}")
    kubectl config set-credentials "$K8S_CLUSTER_NAME-argocd-token-user" --token "$TOKEN"
    kubectl config set-context "$K8S_CLUSTER_NAME-argocd-token-user@$CLUSTER_NAME" \
      --user "$K8S_CLUSTER_NAME-argocd-token-user" \
      --cluster "$CLUSTER_NAME"

    # Add the config setup with the service account you created
    argocd cluster add "$K8S_CLUSTER_NAME-argocd-token-user@$CLUSTER_NAME" --upsert

    # See the clusters added
    argocd cluster list
}

function create_guestbook_app() {
  create_namespace "guestbook"
  CLUSTER_NAME=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='"$K8S_CLUSTER_NAME"')].context.cluster}")
  argocd app create "guestbook" \
    --repo "https://github.com/argoproj/argocd-example-apps.git" \
    --path "guestbook" \
    --dest-server "$(kubectl config view -o jsonpath="{.clusters[?(@.name=='"$CLUSTER_NAME"')].cluster.server}")" \
    --dest-namespace "guestbook" \
    --sync-policy "automated" \
    --upsert
  argocd app list
  read -rp "Would you like to create a load balancer for the guestbook application? " yn
  case $yn in
      [Yy]* ) kubectl -n "guestbook" patch svc "guestbook-ui" -p '{"spec": {"type": "LoadBalancer"}}'; return;;
      * ) return;;
  esac
}

function create_app_production() {
    local app="$1"
    create_namespace "$app-production"
    CLUSTER_NAME=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='"$K8S_CLUSTER_NAME"')].context.cluster}")
    # CURRENT_APP_IMAGE=$(yq e .spec.template.spec.containers[0].image argocd/$app/production/deployment.yaml)
    # IMAGE=$(kustomize build argocd/$app/production | kbld -f - | grep -e 'image:' | awk '{print $NF}')
    # sed -i "s|$CURRENT_APP_IMAGE|$IMAGE|" argocd/$app/production/deployment.yaml
    argocd app create "$app-prod" \
      --repo "https://github.com/malston/tanzu-pipelines.git" \
      --path "argocd/$app/production" \
      --dest-server "$(kubectl config view -o jsonpath="{.clusters[?(@.name=='"$CLUSTER_NAME"')].cluster.server}")" \
      --dest-namespace "$app-production" \
      --sync-policy "automated"
    argocd app list
    wait_for_loadbalancer "$app"
}

function wait_for_loadbalancer() {
    local app="$1"
    echo "Waiting for load balancer to become ready."
    sleep 10
    while kubectl get services "prod-$app-service" -n "$app-production" -o jsonpath='{.status.loadBalancer}' | grep -E '{}' > /dev/null 2>&1; do
        echo -n "..."
        sleep 10
    done
    printf "Access the Production Spring PetClinic UI at: http://%s\n" "$(kubectl get services "prod-$app-service" -n "$app-production" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
}

function main() {
    # shellcheck source=apps/${APP_NAME}.sh
    # shellcheck disable=SC1091
    [[ -f "$1" ]] && source "${1}"

    install_argocli
    configure_argocd

    if [ -n "$APP_NAME" ]; then
      while true; do
          read -rp "Would you like to deploy $APP_NAME to production? " yn
          case $yn in
              [Yy]* ) create_app_production "$APP_NAME"; break;;
              [Nn]* ) exit;;
              * ) echo "Please answer yes or no.";;
          esac
      done
    else
        create_guestbook_app
    fi

    printf "\nAccess the ArgoCD UI at: https://%s\n" "$(kubectl -n argocd get httpproxy argocd -o jsonpath='{.spec.virtualhost.fqdn}')"
    printf "User: %s\n" "admin"
    printf "Password: %s\n\n" "$PASSWD"
}

[[ ! -f "$1" ]] && die "Usage: $0 <path-to-app-manifest>"

main "$@"