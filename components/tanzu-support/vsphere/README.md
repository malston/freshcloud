### Create and then edit .env_development.sh and enter the below values
```console
  $ touch .env_development.sh
  $ vim .env_development.sh

# Deployment defaults
  export DOMAIN='cluster-name.domain.cc'      # Enter the DNS subdomain
  export EMAIL_ADDRESS='nobody@gmail.com'     # E-Mail for CERT registration confirmation
  export PASSWD='my-pass'                     # Password that will be used throughout the project

# vSphere cluster Info
  export MANAGEMENT_CLUSTER_NAME='cluster-name'
```

### Install tanzu cli

Follow these [instructions](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/1.3/vmware-tanzu-kubernetes-grid-13/GUID-install-cli.html) to download and install the tanzu cli bundle.


### Login to management cluster
```console
  $ tanzu login
```

### Create a cluster
```console
  $ bash tanzu-aws-support.sh
```

### Login to workload cluster by getting the kubeconfig
```console
  $ tanzu cluster kubeconfig get freshcloud --admin
```

### Delete existing cluster
```console
  $ bash tanzu-vsphere-support.sh delete
```
