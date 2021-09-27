#!/usr/bin/env bash
#
# Install Production Pipeline

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit; pwd)"

die() {
    2>&1 echo "$@"
    exit 1
}

# shellcheck disable=SC1091
source "${__DIR}/../.env_development.sh" || die "Could not find '.env_development.sh' in root directory"
# shellcheck disable=SC1091
source "${__DIR}/../components/kubernetes-support/kubectl-support.sh" || die "Could not find 'kubectl-support.sh' in ${__DIR}/../components/kubernetes-support directory"

function write_pipeline_params() {
  echo "Writing pipeline params yaml"
  TOKEN_SECRET=$(kubectl get serviceaccount -n argocd argocd -o jsonpath='{.secrets[0].name}')
  TOKEN=$(kubectl get secret -n argocd "$TOKEN_SECRET" -o jsonpath='{.data.token}' | base64 --decode)
  CLUSTER_NAME=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='"$K8S_CLUSTER_NAME"')].context.cluster}")
  CA=$(kubectl get "secret/${TOKEN_SECRET}" -n argocd -o jsonpath='{.data.ca\.crt}')
  SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='"$CLUSTER_NAME"')].cluster.server}")

  # Create a role to be used by concourse to deploy application builds.
  cat <<EOF > "${__DIR}/build/${APP_NAME}/${APP_NAME}-production-params.yml"
domain: ${DOMAIN}
cluster_server: ${SERVER}
argocd_password: ${PASSWD}
kubeconfig: |
  apiVersion: v1
  kind: Config
  clusters:
  - name: ${CLUSTER_NAME}
    cluster:
      certificate-authority-data: ${CA}
      server: ${SERVER}
  contexts:
  - name: $K8S_CLUSTER_NAME-argocd-token-user@$K8S_CLUSTER_NAME
    context:
      cluster: ${CLUSTER_NAME}
      namespace: default
      user: $K8S_CLUSTER_NAME-argocd-token-user
  current-context: $K8S_CLUSTER_NAME-argocd-token-user@$K8S_CLUSTER_NAME
  users:
  - name: $K8S_CLUSTER_NAME-argocd-token-user
    user:
      token: ${TOKEN}
EOF
}

function write_pipeline() {
  echo "Writing pipeline yaml"
  cat <<EOF > "${__DIR}/build/${APP_NAME}/${APP_NAME}-production-pipeline.yml"
jobs:
  - name: install-${APP_NAME}
    plan:
      - task: create-app
        config:
          platform: linux
          image_resource:
            type: registry-image
            source:
              repository: registry.${DOMAIN}/concourse-images/kubectl-docker
              tag: latest
          params:
            KUBECONFIG:
            DOMAIN:
            CLUSTER_SERVER:
            ARGOCD_PASSWORD:
          run:
            path: sh
            args:
            - -ec
            - |
              echo "\$KUBECONFIG" > config.yml
              export KUBECONFIG=config.yml
              # Add the config setup with the service account you created
              argocd login argocd.\$DOMAIN --username admin --password \$ARGOCD_PASSWORD
              echo y | argocd cluster add "$K8S_CLUSTER_NAME-argocd-token-user@$K8S_CLUSTER_NAME" --kubeconfig config.yml --server "argocd.\$DOMAIN" --upsert
              # See the clusters added
              argocd cluster list
              if ! kubectl get namespace "${APP_NAME}-production" > /dev/null 2>&1; then
                kubectl create namespace "${APP_NAME}-production"
              fi
              argocd app create "${APP_NAME}-production" \
                --repo "${APP_DEPLOYMENT_REPO}" \
                --path "argocd/${APP_NAME}/production" \
                --dest-server "\$CLUSTER_SERVER" \
                --dest-namespace "${APP_NAME}-production"
              argocd app list
              printf "\nLogin to the ArgoCD UI at: https://%s\n" "argocd.\$DOMAIN"
          platform: linux
        params:
          KUBECONFIG: ((kubeconfig))
          DOMAIN: ((domain))
          CLUSTER_SERVER: ((cluster_server))
          ARGOCD_PASSWORD: ((argocd_password))

  - name: sync-${APP_NAME}
    plan:
      - task: sync-and-wait
        config:
          platform: linux
          image_resource:
            type: registry-image
            source:
              repository: registry.${DOMAIN}/concourse-images/kubectl-docker
              tag: latest
          params:
            KUBECONFIG:
            DOMAIN:
            CLUSTER_SERVER:
            ARGOCD_PASSWORD:
          run:
            path: sh
            args:
            - -ec
            - |
              echo "\$KUBECONFIG" > config.yml
              export KUBECONFIG=config.yml
              # Add the config setup with the service account you created
              argocd login argocd.\$DOMAIN --username admin --password \$ARGOCD_PASSWORD
              echo y | argocd cluster add "$K8S_CLUSTER_NAME-argocd-token-user@$K8S_CLUSTER_NAME" --kubeconfig config.yml --server "argocd.\$DOMAIN" --upsert
              # See the clusters added
              echo ""
              echo "Synching ${APP_NAME}-production"
              echo ""
              argocd app sync "${APP_NAME}-production"
              echo ""
              echo "Waiting for ${APP_NAME}-production to deploy"
              argocd app wait "${APP_NAME}-production"
              echo ""
              echo "Waiting for load balancer to become ready."
              sleep 5
              while kubectl get services "prod-$APP_NAME-service" -n "$APP_NAME-production" -o jsonpath='{.status.loadBalancer}' | grep -E '{}' > /dev/null 2>&1; do
                  echo -n "..."
                  sleep 5
              done
              echo ""
              echo "App ${APP_NAME}-production is ready"
              echo ""
              argocd app get "${APP_NAME}-production"
              printf "\Access the Spring Petclinic Production App at: http://%s\n" $(kubectl get services "prod-${APP_NAME}-service" -n "${APP_NAME}-production" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
          platform: linux
        params:
          KUBECONFIG: ((kubeconfig))
          DOMAIN: ((domain))
          CLUSTER_SERVER: ((cluster_server))
          ARGOCD_PASSWORD: ((argocd_password))
EOF
}

function fly_pipeline() {
    echo fly login -c "https://ci.${DOMAIN}" -u admin -p "${PASSWD}" -t "${K8S_CLUSTER_NAME}"
    echo y | fly -t "${K8S_CLUSTER_NAME}" set-pipeline -p "deploy-${APP_NAME}-production" \
      -c "${__DIR}/build/${APP_NAME}/${APP_NAME}-production-pipeline.yml" -l "${__DIR}/build/${APP_NAME}/${APP_NAME}-production-params.yml"
    fly -t "${K8S_CLUSTER_NAME}" unpause-pipeline -p "deploy-${APP_NAME}-production"
}

function main() {
    # shellcheck source=apps/${1}.sh
    # shellcheck disable=SC1091
    if [[ -f "$1" ]]; then
        source "${1}" || die "Usage: $0 <path-to-app-manifest>"
    else
        die "Usage: $0 <path-to-app-manifest>"
    fi

    create_namespace "${APP_NAME}-production"
    write_pipeline_params
    write_pipeline
    echo "Deploying the pipeline to Concourse"
    if ! fly_pipeline; then
        fly -t "${K8S_CLUSTER_NAME}" sync > /dev/null 2>&1
        if ! fly_pipeline; then
        echo ""
        echo "Failed to add ${APP_NAME}. Manual cleanup needed."
        exit 1
        fi
    fi
    echo ""
    echo "${APP_NAME}-production added succesfully!"
}

main "$@"
