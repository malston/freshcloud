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
    register_cluster
    create_guestbook_app
    printf "Access the ArgoCD UI at: https://%s\n" "$(kubectl get httpproxy argocd -o jsonpath='{.spec.virtualhost.fqdn}')"
    printf "User: %s\n" "admin"
    printf "Password: %s" "$PASSWD"
}

function login_argocd() {
    argocd login "$(kubectl get httpproxy argocd -o jsonpath='{.spec.virtualhost.fqdn}')" --username admin --password "$PASSWD"
}

function register_cluster() {
    # Create kubeconfig context with Service Account secret
    TOKEN_SECRET=$(kubectl get serviceaccount -n argocd argocd -o jsonpath='{.secrets[0].name}')
    TOKEN=$(kubectl get secret -n argocd "$TOKEN_SECRET" -o jsonpath='{.data.token}' | base64 --decode)
    CLUSTER_NAME=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='"$K8S_CLUSTER_NAME"')].context.cluster}")
    kubectl config set-credentials "$K8S_CLUSTER_NAME-argocd-token-user" --token "$TOKEN"
    kubectl config set-context "$K8S_CLUSTER_NAME-argocd-token-user@$CLUSTER_NAME" \
      --user "$K8S_CLUSTER_NAME-argocd-token-user" \
      --cluster "$CLUSTER_NAME"

    # Add the config setup with the service account you created
    argocd cluster add "$K8S_CLUSTER_NAME-argocd-token-user@$CLUSTER_NAME"

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
    --sync-policy "automated"
  argocd app list
  kubectl -n guestbook patch svc guestbook-ui -p '{"spec": {"type": "LoadBalancer"}}'
}

function create_spring_petclinic_development() {
    create_namespace "spring-petclinic-development"
    CLUSTER_NAME=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='"$K8S_CLUSTER_NAME"')].context.cluster}")
    argocd app create "spring-petclinic-dev" \
      --repo "https://github.com/malston/tanzu-pipelines.git" \
      --path "argocd/spring-petclinic/dev" \
      --dest-server "$(kubectl config view -o jsonpath="{.clusters[?(@.name=='"$CLUSTER_NAME"')].cluster.server}")" \
      --dest-namespace "spring-petclinic-development" \
      --sync-policy "automated"
    argocd app list
}

function create_spring_petclinic_production() {
    create_namespace "spring-petclinic-production"
    CLUSTER_NAME=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='"$K8S_CLUSTER_NAME"')].context.cluster}")
    # CURRENT_APP_IMAGE=$(yq e .spec.template.spec.containers[0].image argocd/spring-petclinic/production/deployment.yaml)
    # IMAGE=$(kustomize build argocd/spring-petclinic/production | kbld -f - | grep -e 'image:' | awk '{print $NF}')
    # sed -i "s|$CURRENT_APP_IMAGE|$IMAGE|" argocd/spring-petclinic/production/deployment.yaml
    argocd app create "spring-petclinic-prod" \
      --repo "https://github.com/malston/tanzu-pipelines.git" \
      --path "argocd/spring-petclinic/production" \
      --dest-server "$(kubectl config view -o jsonpath="{.clusters[?(@.name=='"$CLUSTER_NAME"')].cluster.server}")" \
      --dest-namespace "spring-petclinic-production" \
      --sync-policy "automated"
    argocd app list
    wait_for_loadbalancer
}

function wait_for_loadbalancer() {
    echo "Waiting for load balancer to become ready."
    while kubectl get services prod-spring-petclinic-service -n spring-petclinic-production -o jsonpath='{.status.loadBalancer}' | grep -E '{}' > /dev/null 2>&1; do
        echo -n "..."
        sleep 10
    done
    printf "Access the Production Spring PetClinic UI at: http://%s\n" "$(kubectl get services prod-spring-petclinic-service -n spring-petclinic-production -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
}

function main() {
    install_argocli
    configure_argocd
    create_spring_petclinic_development
    create_spring_petclinic_production
}

main