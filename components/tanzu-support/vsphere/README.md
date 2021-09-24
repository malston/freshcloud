### Create and then edit .env_development.sh and enter the below values
```console
  $ touch .env_development.sh
  $ vim .env_development.sh

  # deployment defaults
  export DOMAIN='cluster-name.domain.cc'      # Enter the DNS subdomain
  export EMAIL_ADDRESS='nobody@gmail.com'     # E-Mail for CERT registration confirmation
  export PASSWD='my-pass'                     # Password that will be used throughout the project

  # vsphere cluster info
  export CONTROL_PLANE_IP=10.1.1.10                # The supervisor cluster IP
  export MANAGEMENT_CLUSTER_NAME="wcp.example.com" # The supervisor cluster name

  # kubernetes cluster name (defaults to freshcloud)
  export K8S_CLUSTER_NAME='dev'
  export K8S_NAMESPACE='ns1'

  export CHALLENGE_TYPE='http' # challenge type for cert-manager, defaults to 'http'

  # dns zone credentials (only necessary for 'dns' certificate challenge)
  export ZONE_ID='REDACTED'
  export AWS_ACCESS_KEY_ID='REDACTED'
  export AWS_SECRET_ACCESS_KEY='REDACTED'

  # credentials for network.pivotal.io (only necessary if deploying the tanzu build service)
  export PIVOTAL_REGISTRY_USER='nobody@gmail.com'
  export PIVOTAL_REGISTRY_PASSWORD='REDACTED'

  # credentials for pulling images from docker to avoid rate limiting ImagePullBack errors
  export DOCKER_USERNAME='nobody@gmail.com'
  export DOCKER_PASSWORD='REDACTED'
```

### Install tanzu CLI

Follow these [instructions](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/1.3/vmware-tanzu-kubernetes-grid-13/GUID-install-cli.html) to download and install the tanzu CLI bundle.

On vSphere 7 and later, the vSphere with Tanzu feature includes a Supervisor Cluster that you can configure as a management cluster for Tanzu Kubernetes Grid, which we assume you've done already before following these instructions.

Follow these [instructions](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/1.3/vmware-tanzu-kubernetes-grid-13/GUID-tanzu-k8s-clusters-connect-vsphere7.html) to use the tanzu CLI with a Supervisor cluster. This will take you through the steps to connect to the Supervisor Cluster and add it as a Management Cluster to the tanzu CLI.

### Login to management cluster
```console
  $ tanzu login
```

### Create a cluster
```console
  $ bash tanzu-vsphere-support.sh
```

### Login to workload cluster by getting the kubeconfig
```console
  $ tanzu cluster kubeconfig get freshcloud --namespace development --admin
```

### Delete existing cluster
```console
  $ bash tanzu-vsphere-support.sh delete
```
