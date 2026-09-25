# Changelog

## 0.1.0 (2026-09-25)


### ⚠ BREAKING CHANGES

* **aws:** cluster_support_type is gone.
* **aws:** crossplane_service_account_namespace, crossplane_service_account_name and crossplane_policy_arns are gone, along with the crossplane_role_arn, ebs_csi_role_arn and crossplane_service_account_kubernetes_binding outputs.
* **aws:** take the four EKS add-ons out of the module

### Features

* **aws:** drop the workload identities — they belong to the plugins ([4ebf965](https://github.com/do-now-io/socle/commit/4ebf9654072b2e47b21c76206d36b4513d206566))
* **aws:** encrypt both log groups with a customer-managed key ([998af3e](https://github.com/do-now-io/socle/commit/998af3ee16c30cc30af57b4804f2ebfb21c910af))
* **aws:** make extended support impossible rather than discouraged ([3acdcfd](https://github.com/do-now-io/socle/commit/3acdcfda56638a4df325faffacd82a74c93815cf))
* **aws:** take the four EKS add-ons out of the module ([99164df](https://github.com/do-now-io/socle/commit/99164dffe6fe307605a34951acf2fb637f3ee9aa))
* **aws:** the AWS foundations OpenTofu module ([0a08721](https://github.com/do-now-io/socle/commit/0a087212dd7566e95bebdd0d52eeea3bf119439d))
* **azure:** foundations module — VNet, AKS Standard + NAP, identities ([5251c78](https://github.com/do-now-io/socle/commit/5251c780f86bbde2ff761c3bd523ad29be6c9293))
* **bootstrap:** the module — inputs only, Flux Operator renders the catalog ([fae5893](https://github.com/do-now-io/socle/commit/fae5893ff60f084d1815af892011f4093075ac14))
* **catalog:** the artifact — hello module, one overlay per cloud, the cloud's colour ([256e416](https://github.com/do-now-io/socle/commit/256e4165997e32044fd00d06292e7039e7f2faf3))
* **ci:** publish and sign the artifact, prove it on floci, release it from the conventional commits ([a36212e](https://github.com/do-now-io/socle/commit/a36212e3a94b4641f16a5b2d63e6e7cc5027568f))
* **clusters:** the AWS root — one apply, one tfvars, one version ([dff54c7](https://github.com/do-now-io/socle/commit/dff54c70bbb249cbe707d1f0e5721f6b979686a5))
* **foundations:** a helm_kubernetes output on every cloud, stamped with the socle version ([91fe476](https://github.com/do-now-io/socle/commit/91fe4762e5945e3ad1bf8fa48f9c26f202e90925))
* **gcp:** the GCP foundations OpenTofu module ([2347c8a](https://github.com/do-now-io/socle/commit/2347c8a99368d5099307fd1eefdc408dc05f1276))
* **registry:** the artifact lives at socle/flux-modules, the OpenTofu modules at socle/opentofu-modules ([7f8cef2](https://github.com/do-now-io/socle/commit/7f8cef2677483d016b28553993591a619ca6b395))
* **scaleway:** the Scaleway foundations OpenTofu module ([9f8dda5](https://github.com/do-now-io/socle/commit/9f8dda52f84c10d7d2e86231e5918034983ed51d))


### Bug Fixes

* **aws:** grant the applier cluster-admin explicitly, not by default ([d23fc54](https://github.com/do-now-io/socle/commit/d23fc546a2eb4d12c8294eec800b538f5966c331))
* **aws:** move the example back to eu-west-3 ([d6efd84](https://github.com/do-now-io/socle/commit/d6efd8465e78b94073c18ce6b547bf76e18e2968))
* **azure:** address the three Trivy findings on PR [#25](https://github.com/do-now-io/socle/issues/25) ([43f06a4](https://github.com/do-now-io/socle/commit/43f06a4fdb3ec810c4a91c728251633c7a856afd))
* **azure:** converge upgrade_settings drift, expose zones/vm_size overrides ([c3da35d](https://github.com/do-now-io/socle/commit/c3da35d7ae131aecac14cc0216dab89d529e08e6))
* **azure:** drop the cross-cloud comparison from the NAT Gateway note ([30fa72c](https://github.com/do-now-io/socle/commit/30fa72c76fe5ef65b57638bf7c63a03dc87baf27))
