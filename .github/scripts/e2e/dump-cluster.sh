#!/usr/bin/env bash
# What the cluster looked like when an e2e job failed. Never fails itself.
kubectl -n flux-system get resourceset,ocirepository,gitrepository,kustomization -o wide || true
kubectl get ns hello -o wide || true
kubectl -n crossplane-system get helmrelease,helmrepository,helmchart,deploy,pod -o wide || true
kubectl get provider.pkg.crossplane.io || true
kubectl -n e2e-probe get managed -o wide || true
kubectl -n flux-system get ocirepository socle \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}' || true
kubectl -n flux-system logs deploy/flux-operator --tail=80 || true
