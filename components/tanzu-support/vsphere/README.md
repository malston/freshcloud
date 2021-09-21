### Create and then edit .env_development.sh and enter the below values
```console
  $ touch .env_development.sh
  $ vim .env_development.sh

# Deployment defaults
  export DOMAIN='cluster-name.domain.cc'      # Enter the DNS subdomain
  export EMAIL_ADDRESS='nobody@gmail.com'     # E-Mail for CERT registration confirmation
  export PASSWD='my-pass'                     # Password that will be used throughout the project

# vSphere cluster Info
  export CONTROL_PLANE_IP=10.213.206.65                        # The supervisor cluster IP
  export MANAGEMENT_CLUSTER_NAME="wcp.haas-402.pez.vmware.com" # The supervisor cluster name
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
