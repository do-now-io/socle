#!/usr/bin/env bash
# What the cluster looked like when an e2e job failed. Never fails itself.
kubectl -n flux-system get resourceset,ocirepository,gitrepository,kustomization -o wide || true
kubectl get ns hello -o wide || true
kubectl -n flux-system get ocirepository socle \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}' || true
kubectl -n flux-system logs deploy/flux-operator --tail=80 || true
