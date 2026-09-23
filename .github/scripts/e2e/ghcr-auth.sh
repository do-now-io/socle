#!/usr/bin/env bash
# The package is private, so the pull needs a credential — created in the
# cluster after the apply, from the workflow's own token (GHCR_TOKEN), so that
# no credential ever enters OpenTofu. The OCIRepository is already pointed at
# the secret by name; the annotation just skips the retry backoff.
#   usage: ghcr-auth.sh <eks cluster name>     (needs KUBECONFIG, GHCR_TOKEN)
set -euo pipefail
aws eks update-kubeconfig --name "$1" --kubeconfig "$KUBECONFIG" > /dev/null
kubectl -n flux-system create secret docker-registry ghcr-auth \
  --docker-server=ghcr.io \
  --docker-username="$GITHUB_ACTOR" \
  --docker-password="$GHCR_TOKEN"
for _ in $(seq 1 60); do
  if kubectl -n flux-system get ocirepository socle > /dev/null 2>&1; then
    kubectl -n flux-system annotate ocirepository socle \
      reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
    exit 0
  fi
  sleep 2
done
echo "::error::the operator never created ocirepository/socle"
exit 1
