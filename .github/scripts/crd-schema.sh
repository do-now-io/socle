#!/usr/bin/env bash
# A kubeconform schema from a CustomResourceDefinition, for a kind the datree
# catalog lacks or serves broken: every served version's openAPIV3Schema,
# written as <schemas-dir>/<group>/<kind>_<version>.json — kubeconform's
# {{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}} layout, the one
# pr-static.yaml already lays the flux-operator's schemas out in. Every object
# that lists its properties is closed (additionalProperties: false), as datree
# closes its own: -strict then refuses a misspelt field.
#
# Usage: crd-schema.sh <crd-url> <schemas-dir>
set -euo pipefail
url="${1:?usage: $0 <crd-url> <schemas-dir>}"
dir="${2:?usage: $0 <crd-url> <schemas-dir>}"
crd="$(mktemp)"
trap 'rm -f "${crd}"' EXIT
curl -sfL --retry 3 "${url}" -o "${crd}" || { echo "::error::cannot fetch ${url}"; exit 1; }
group="$(yq '.spec.group' "${crd}")"
kind="$(yq '.spec.names.kind | downcase' "${crd}")"
mkdir -p "${dir}/${group}"
for version in $(yq '.spec.versions[].name' "${crd}"); do
  version="${version}" yq -o=json '
    .spec.versions[] | select(.name == strenv(version)) | .schema.openAPIV3Schema
    | (.. | select(tag == "!!map" and .type == "object" and has("properties")
        and (has("additionalProperties") | not)
        and (has("x-kubernetes-preserve-unknown-fields") | not)))
      |= . + {"additionalProperties": false}' "${crd}" \
    > "${dir}/${group}/${kind}_${version}.json"
  echo "${dir}/${group}/${kind}_${version}.json"
done
