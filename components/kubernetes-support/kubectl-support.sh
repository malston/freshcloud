#!/usr/bin/env bash

function wait_for_ready() {
  namespace="$1"
  echo "Waiting for pods in $namespace to become ready."
  while true; do
    status=$(kubectl get pods -n "$namespace" | grep -Ev 'Running|NAME|Completed')
    if [ -z "$status" ]; then
      break
    fi
  done
  echo "All pods are running."
}

function create_namespace() {
  namespace="${1:?"Namespace is required"}"
  if ! kubectl get namespace "${namespace}" > /dev/null 2>&1; then
    kubectl create namespace "${namespace}"
  fi
}

function create_docker_registry_secret() {
  namespace="${1:?"Namespace is required"}"
  secret_name="${2:-registry-credentials}"
  echo "Creating docker-registry secret for $secret_name"
  kubectl create secret docker-registry "$secret_name" \
      --docker-username="$DOCKER_USERNAME" \
      --docker-password="$DOCKER_PASSWORD" \
      --docker-server="https://docker.io" \
      --namespace "$namespace"
}