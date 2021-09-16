#!/usr/bin/env bash

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit; pwd)"

die() {
    2>&1 echo "$@"
    exit 1
}

# shellcheck disable=SC1091
source "${__DIR}/../.env_development.sh" || die "Could not find '.env_development.sh' in root directory"

if [ -z "$1" ]; then
  echo "$0 <gcp|aws|azure|tanzu-aws|tanzu-vsphere>"
fi

if [ "$1" = 'gcp' ]; then
  cd "${__DIR}"/../components/google-cloud-support/ && ./google-cloud-support.sh
elif [ "$1" = 'aws' ]; then
  cd "${__DIR}"/../components/aws-support/ && ./aws-cloud-support.sh
elif [ "$1" = 'azure' ]; then
  cd "${__DIR}"/../components/azure-support/ && ./azure-cloud-support.sh
elif [ "$1" = 'tanzu-aws' ]; then
  cd "${__DIR}"/../components/tanzu-support/aws || die "Could not cd into ${__DIR}/../components/tanzu-support/aws from $PWD"
  if [ "$2" == 'mgmt' ]; then
    ./tanzu-aws-support.sh 'mgmt'
  else
    ./tanzu-aws-support.sh
  fi
elif [ "$1" = 'tanzu-vsphere' ]; then
  cd "${__DIR}"/../components/tanzu-support/vsphere || die "Could not cd into ${__DIR}/../components/tanzu-support/vsphere from $PWD"
    ./tanzu-vsphere-support.sh
fi
