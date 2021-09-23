# Container to run in our pipeline with kubectl installed.
FROM alpine:3.8

ARG KUBE_VERSION="v1.18.10"

RUN apk add --update ca-certificates \
 && apk add --update -t deps curl \
 && apk add --update gettext \
 && apk add --update jq \
 && apk add --update git \
 && curl -L https://storage.googleapis.com/kubernetes-release/release/${KUBE_VERSION}/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl \
 && chmod +x /usr/local/bin/kubectl \
 && curl -sSL https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 -o /usr/local/bin/argocd \
 && chmod +x /usr/local/bin/argocd \
 && apk del --purge deps \
 && rm /var/cache/apk/*
