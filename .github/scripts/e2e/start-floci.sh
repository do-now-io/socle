#!/usr/bin/env bash
# floci runs a real k3s behind its emulated EKS once the Docker socket is
# mounted and FLOCI_SERVICES_EKS_MOCK is left unset. Shared by the two e2e
# jobs in publish-artifact.yaml.
set -euo pipefail
docker run -d --name floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  floci/floci:1.5.34
for _ in $(seq 1 60); do
  curl -fs http://localhost:4566/_localstack/health > /dev/null && exit 0
  sleep 2
done
echo "::error::floci never became healthy"
docker logs floci
exit 1
