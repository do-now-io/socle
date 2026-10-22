#!/usr/bin/env python3
"""The charts' values.schema.json, written from one set of definitions.

webapp and cronjob read the same blocks (image, env, resources,
securityContext, volumes, the objects they create…) through the socle-lib
library: their schemas share these blocks too, defined once here. Run it
after a change to either chart's values and commit both files; CI checks they
are up to date (`--check`).

    python3 .github/scripts/charts-schema.py [--check]
"""
import json
import os
import sys


DNS_LABEL = "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$"
QUANTITY = {"oneOf": [
    {"type": "string", "pattern": "^[0-9]+(\\.[0-9]+)?(m|k|M|G|T|P|E|Ki|Mi|Gi|Ti|Pi|Ei)?$"},
    {"type": "number", "exclusiveMinimum": 0}]}
INT_OR_PERCENT = {"oneOf": [
    {"type": "integer", "minimum": 0},
    {"type": "string", "pattern": "^[0-9]+%$"}]}

def obj(props, required=(), extra=False, **kw):
    s = {"type": "object", "properties": props, "additionalProperties": extra}
    if required:
        s["required"] = list(required)
    s.update(kw)
    return s

def arr(items, **kw):
    return {"type": "array", "items": items, **kw}

ref = lambda name: {"$ref": "#/definitions/" + name}

definitions = {
    "name": {"type": "string", "pattern": DNS_LABEL, "maxLength": 40},
    "image": obj({
        "registry": {"type": "string",
                     "pattern": "^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]+)?(/[a-z0-9]([a-z0-9._-]*[a-z0-9])?)*$"},
        "repository": {"type": "string",
                       "pattern": "^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*$"},
        # null is unset: a values file can drop the tag another one set, for a digest.
        # A tag may carry its digest, <tag>@sha256:<hex>: what Argo CD Image
        # Updater's digest strategy writes into image.tag. latest stays refused,
        # with or without one.
        "tag": {"type": ["string", "null"],
                "pattern": "^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}(@sha256:[a-f0-9]{64})?$",
                "not": {"type": "string", "pattern": "^latest(@|$)"}},
        "digest": {"type": ["string", "null"], "pattern": "^sha256:[a-f0-9]{64}$"},
        "pullPolicy": {"enum": ["Always", "IfNotPresent", "Never"]},
        "imagePullSecrets": arr(obj({"name": {"type": "string", "minLength": 1}}, ["name"])),
    }, ["registry", "repository"],
        oneOf=[{"required": ["tag"], "properties": {"tag": {"type": "string"}, "digest": {"type": "null"}}},
               {"required": ["digest"], "properties": {"digest": {"type": "string"}, "tag": {"type": "null"}}}]),
    "env": arr(obj({
        "name": {"type": "string", "minLength": 1},
        "value": {"type": "string"},
        "valueFrom": {"type": "object"},
    }, ["name"], not_=None)),
    "envFrom": arr(obj({
        "configMapRef": obj({"name": {"type": "string", "minLength": 1}, "optional": {"type": "boolean"}}, ["name"]),
        "secretRef": obj({"name": {"type": "string", "minLength": 1}, "optional": {"type": "boolean"}}, ["name"]),
        "prefix": {"type": "string"},
    }, oneOf=[{"required": ["configMapRef"]}, {"required": ["secretRef"]}])),
    "resourceList": {"type": "object",
                     "propertyNames": {"pattern": "^(cpu|memory|ephemeral-storage|hugepages-.+|[a-z0-9.-]+/[a-z0-9._-]+)$"},
                     "additionalProperties": QUANTITY},
    "resources": obj({
        "requests": {"allOf": [ref("resourceList"), {"required": ["cpu", "memory"]}]},
        "limits": ref("resourceList"),
    }, ["requests"]),
    "securityContext": obj({
        "runAsUser": {"type": "integer", "minimum": 1},
        "runAsGroup": {"type": "integer", "minimum": 1},
        "fsGroup": {"type": "integer", "minimum": 1},
        "netBindService": {"type": "boolean"},
    }, ["runAsUser"]),
    # The restricted profile's volume types (restrict-volume-types).
    "volumes": arr(obj({
        "name": {"type": "string", "pattern": DNS_LABEL, "not": {"const": "tmp"}},
        **{t: {"type": "object"} for t in ["configMap", "secret", "emptyDir", "projected", "downwardAPI",
                                           "persistentVolumeClaim", "csi", "ephemeral"]},
    }, ["name"], minProperties=2, maxProperties=2)),
    "volumeMounts": arr(obj({
        "name": {"type": "string", "minLength": 1},
        "mountPath": {"type": "string", "pattern": "^/"},
        "subPath": {"type": "string"},
        "subPathExpr": {"type": "string"},
        "readOnly": {"type": "boolean"},
    }, ["name", "mountPath"])),
    "textData": {"type": "object", "minProperties": 1,
                 "propertyNames": {"pattern": "^[-._a-zA-Z0-9]+$"},
                 "additionalProperties": {"type": "string"}},
    "configMaps": arr(obj({"name": ref("name"), "data": ref("textData")}, ["name", "data"])),
    "secrets": arr(obj({"name": ref("name"), "stringData": ref("textData")}, ["name", "stringData"])),
    "externalSecrets": arr(obj({
        "name": ref("name"),
        "secretStoreRef": obj({
            "kind": {"enum": ["SecretStore", "ClusterSecretStore"]},
            "name": {"type": "string", "minLength": 1},
        }, ["kind", "name"]),
        "data": arr(obj({
            "secretKey": {"type": "string", "pattern": "^[-._a-zA-Z0-9]+$"},
            "remoteRef": obj({
                "key": {"type": "string", "minLength": 1},
                "property": {"type": "string", "minLength": 1},
                "version": {"type": "string", "minLength": 1},
            }, ["key"]),
        }, ["secretKey", "remoteRef"]), minItems=1),
    }, ["name", "secretStoreRef", "data"])),
    "persistence": arr(obj({
        "name": ref("name"),
        "size": QUANTITY,
        "accessModes": arr({"enum": ["ReadWriteOnce", "ReadWriteOncePod", "ReadOnlyMany", "ReadWriteMany"]},
                           minItems=1, uniqueItems=True),
        "storageClassName": {"type": "string", "minLength": 1},
        "keep": {"type": "boolean"},
    }, ["name", "size"])),
    "serviceAccount": obj({
        "automountServiceAccountToken": {"type": "boolean"},
        "annotations": {"type": "object", "additionalProperties": {"type": "string"}},
    }),
    "nodeSelector": {"type": "object", "additionalProperties": {"type": "string"}},
    "tolerations": arr({"type": "object"}),
    "affinity": {"type": "object"},
    "stringList": arr({"type": "string"}),
    "switch": obj({"enabled": {"type": "boolean"}}, ["enabled"]),
}
# env: a value or a valueFrom, never both.
definitions["env"]["items"]["not"] = {"required": ["value", "valueFrom"]}
del definitions["env"]["items"]["not_"]

probe = obj({
    "httpGet": {"type": "object", "required": ["port"]},
    "tcpSocket": {"type": "object", "required": ["port"]},
    "grpc": {"type": "object", "required": ["port"]},
    "exec": {"type": "object", "required": ["command"]},
    **{k: {"type": "integer", "minimum": 0} for k in [
        "initialDelaySeconds", "periodSeconds", "timeoutSeconds", "successThreshold",
        "failureThreshold", "terminationGracePeriodSeconds"]},
}, oneOf=[{"required": [h]} for h in ["httpGet", "tcpSocket", "grpc", "exec"]])
definitions["probe"] = probe

route = obj({
    "name": ref("name"),
    "parentRefs": arr(obj({
        "name": {"type": "string", "minLength": 1},
        "namespace": {"type": "string", "pattern": DNS_LABEL},
        "sectionName": {"type": "string", "minLength": 1},
        "port": {"type": "integer", "minimum": 1, "maximum": 65535},
    }, ["name"]), minItems=1),
    "hostnames": arr({"type": "string", "minLength": 1}),
    # Gateway API's own rules, copied as is, but for backendRefs: the chart's.
    "rules": arr({"type": "object", "properties": {"backendRefs": False}}, minItems=1),
}, ["name", "parentRefs", "rules"])


SHARED = {
    "image": ref("image"),
    "commonEnv": ref("env"),
    "env": ref("env"),
    "resources": ref("resources"),
    "securityContext": ref("securityContext"),
    "commonEnvFrom": ref("envFrom"),
    "envFrom": ref("envFrom"),
    "volumes": ref("volumes"),
    "volumeMounts": ref("volumeMounts"),
    "configMaps": ref("configMaps"),
    "secrets": ref("secrets"),
    "externalSecrets": ref("externalSecrets"),
    "persistence": ref("persistence"),
    "serviceAccount": ref("serviceAccount"),
    "nodeSelector": ref("nodeSelector"),
    "tolerations": ref("tolerations"),
    "affinity": ref("affinity"),
    "command": ref("stringList"),
    "args": ref("stringList"),
    "terminationGracePeriodSeconds": {"type": "integer", "minimum": 0},
}
SHARED_REQUIRED = ["image", "resources", "securityContext"]

WEBAPP = {
        "image": ref("image"),
        "commonEnv": ref("env"),
        "env": ref("env"),
        "port": {"type": "integer", "minimum": 1, "maximum": 65535},
        "livenessProbe": ref("probe"),
        "readinessProbe": ref("probe"),
        "resources": ref("resources"),
        "securityContext": ref("securityContext"),
        "routes": arr(route),
        "commonEnvFrom": ref("envFrom"),
        "envFrom": ref("envFrom"),
        "volumes": ref("volumes"),
        "volumeMounts": ref("volumeMounts"),
        "configMaps": ref("configMaps"),
        "secrets": ref("secrets"),
        "externalSecrets": ref("externalSecrets"),
        "persistence": ref("persistence"),
        "serviceAccount": ref("serviceAccount"),
        "nodeSelector": ref("nodeSelector"),
        "tolerations": ref("tolerations"),
        "affinity": ref("affinity"),
        "topologySpread": obj({"whenUnsatisfiable": {"enum": ["ScheduleAnyway", "DoNotSchedule"]}},
                              ["whenUnsatisfiable"]),
        "replicas": {"type": "integer", "minimum": 0},
        "autoscaling": obj({
            "enabled": {"type": "boolean"},
            "minReplicas": {"type": "integer", "minimum": 1},
            "maxReplicas": {"type": "integer", "minimum": 1},
            "targetCPUUtilizationPercentage": {"type": "integer", "minimum": 1},
        }, ["enabled", "minReplicas", "maxReplicas", "targetCPUUtilizationPercentage"]),
        "podDisruptionBudget": obj({
            "enabled": {"type": "boolean"},
            "maxUnavailable": {"oneOf": [{"type": "integer", "minimum": 1},
                                         {"type": "string", "pattern": "^[1-9][0-9]*%$"}]},
        }, ["enabled", "maxUnavailable"]),
        "strategy": obj({
            "type": {"enum": ["RollingUpdate", "Recreate"]},
            "rollingUpdate": obj({"maxSurge": INT_OR_PERCENT, "maxUnavailable": INT_OR_PERCENT}),
        }, ["type"],
            **{"if": {"properties": {"type": {"const": "Recreate"}}},
               "then": {"not": {"required": ["rollingUpdate"]}}}),
        "command": ref("stringList"),
        "args": ref("stringList"),
        "reloader": ref("switch"),
        "metrics": obj({
            "enabled": {"type": "boolean"},
            "port": {"type": "integer", "minimum": 1, "maximum": 65535},
            "path": {"type": "string", "pattern": "^/"},
        }, ["enabled", "path"]),
        "terminationGracePeriodSeconds": {"type": "integer", "minimum": 0},
}

CRONJOB = {
    "schedule": {"type": "string", "minLength": 9},
    "timeZone": {"type": "string", "pattern": "^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)*$"},
    "suspend": {"type": "boolean"},
    "concurrencyPolicy": {"enum": ["Allow", "Forbid", "Replace"]},
    "successfulJobsHistoryLimit": {"type": "integer", "minimum": 0},
    "failedJobsHistoryLimit": {"type": "integer", "minimum": 0},
    "startingDeadlineSeconds": {"type": "integer", "minimum": 1},
    "backoffLimit": {"type": "integer", "minimum": 0},
    "activeDeadlineSeconds": {"type": "integer", "minimum": 1},
    "restartPolicy": {"enum": ["Never", "OnFailure"]},
    **SHARED,
}


def chart_schema(title, properties, required):
    used = set()

    def walk(node):
        if isinstance(node, dict):
            r = node.get("$ref")
            if r and r not in used:
                used.add(r)
                walk(definitions[r.rsplit("/", 1)[1]])
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(properties)
    return {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "title": title,
        "type": "object",
        "additionalProperties": False,
        "required": required,
        # Helm adds the library's values and the global ones to every chart's.
        "properties": {**properties, "socle-lib": {"type": "object"}, "global": {"type": "object"}},
        "definitions": {k: v for k, v in definitions.items() if "#/definitions/" + k in used},
    }


CHARTS = {
    "webapp": chart_schema("webapp", WEBAPP, ["image", "port", "livenessProbe", "readinessProbe",
                                              "resources", "securityContext"]),
    "cronjob": chart_schema("cronjob", CRONJOB, ["schedule", "activeDeadlineSeconds"] + SHARED_REQUIRED),
}

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "charts")
stale = []
for chart, schema in CHARTS.items():
    path = os.path.join(root, chart, "values.schema.json")
    text = json.dumps(schema, indent=2) + "\n"
    if "--check" in sys.argv:
        if not os.path.exists(path) or open(path).read() != text:
            stale.append(path)
    else:
        open(path, "w").write(text)
if stale:
    sys.exit("out of date, run .github/scripts/charts-schema.py: " + ", ".join(stale))
