#!/usr/bin/env bash
#
# Install KPack

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit; pwd)"

die() {
    2>&1 echo "$@"
    exit 1
}

# shellcheck disable=SC1091
source "${__DIR}/../.env_development.sh" || die "Could not find '.env_development.sh' in root directory"
# shellcheck disable=SC1091
source "${__DIR}/../components/kubernetes-support/kubectl-support.sh" || die "Could not find 'kubectl-support.sh' in ${__DIR}/../components/kubernetes-support directory"

function kube_install_kpack() {
  kubectl apply -f https://github.com/pivotal/kpack/releases/download/v0.3.1/release-0.3.1.yaml
}

function build_docker_container() {
  echo "Building images: kubectl-docker:latest"
  echo "${PASSWD}" | docker login -u admin "https://registry.${DOMAIN}" --password-stdin

  # Container: pipeline talks to k8s
  docker build --platform "linux/amd64" --rm -t "registry.${DOMAIN}/concourse-images/kubectl-docker:latest" .
  docker push "registry.${DOMAIN}/concourse-images/kubectl-docker:latest"

  # Container: pipeline talks to kpack
  docker pull "gcr.io/cf-build-service-public/concourse-kpack-resource:1.0"
  docker tag "gcr.io/cf-build-service-public/concourse-kpack-resource:1.0" "registry.${DOMAIN}/concourse-images/concourse-kpack-resource:1.0"
  docker push "registry.${DOMAIN}/concourse-images/concourse-kpack-resource:1.0"
}

function create_heroku_cluster_stack_kpack() {
  cat <<EOF | kubectl apply -f -
apiVersion: kpack.io/v1alpha1
kind: ClusterStack
metadata:
  name: base
spec:
  id: "heroku-20"
  buildImage:
    image: "heroku/pack:20-build"
  runImage:
    image: "heroku/pack:20"
EOF
}

function create_heroku_cluster_store_kpack() {
  cat <<EOF | kubectl apply -f -
apiVersion: kpack.io/v1alpha1
kind: ClusterStore
metadata:
  name: default
spec:
  sources:
  - image: heroku/buildpacks:20
EOF
}

build_docker_container
kube_install_kpack
wait_for_ready kpack
create_heroku_cluster_stack_kpack
create_heroku_cluster_store_kpack
