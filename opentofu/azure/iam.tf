# Identities — docs/azure/managed-scope.md (Microsoft Entra Workload ID).
#
# No resource in this file. Unlike EKS, which assumes an explicit IAM role
# to manage ENIs, security groups and load balancers on the consumer's
# behalf, AKS's own control-plane identity is inline: the `identity` block
# on azurerm_kubernetes_cluster in cluster.tf is enough, Azure creates and
# manages that identity itself. There is no structural equivalent of
# iam.tf's aws_iam_role.cluster to create here.
#
# No identity for the in-cluster Crossplane provider either, and none for
# anything else the layer above installs — same reasoning as AWS's Pod
# Identity and GCP's workload-identity outputs: a federated credential is
# only half an identity, the other half is a Kubernetes service account
# that does not exist until the plugins are deployed. What this module
# enables is the mechanism that binding will need — workload_identity_enabled
# and oidc_issuer_enabled on the cluster resource, and the OIDC issuer URL
# as an output — not the binding itself.
