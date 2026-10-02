# Changelog

## 0.1.0 (2026-10-02)


### ⚠ BREAKING CHANGES

* **aws:** cluster_support_type is gone.
* **aws:** crossplane_service_account_namespace, crossplane_service_account_name and crossplane_policy_arns are gone, along with the crossplane_role_arn, ebs_csi_role_arn and crossplane_service_account_kubernetes_binding outputs.
* **aws:** take the four EKS add-ons out of the module

### Features

* **aws:** Crossplane's identity, and the boundary of every role it creates ([22988d9](https://github.com/do-now-io/socle/commit/22988d9295b0855f66a0ddec79f299af9ba3e094))
* **aws:** drop the workload identities — they belong to the plugins ([4ebf965](https://github.com/do-now-io/socle/commit/4ebf9654072b2e47b21c76206d36b4513d206566))
* **aws:** EKS add-ons once compute exists, the shared Gateways, and external-dns wired end to end ([32b2bda](https://github.com/do-now-io/socle/commit/32b2bda98fd71adae6959f901900de67faa89965))
* **aws:** encrypt both log groups with a customer-managed key ([998af3e](https://github.com/do-now-io/socle/commit/998af3ee16c30cc30af57b4804f2ebfb21c910af))
* **aws:** make extended support impossible rather than discouraged ([3acdcfd](https://github.com/do-now-io/socle/commit/3acdcfda56638a4df325faffacd82a74c93815cf))
* **aws:** take the four EKS add-ons out of the module ([99164df](https://github.com/do-now-io/socle/commit/99164dffe6fe307605a34951acf2fb637f3ee9aa))
* **aws:** the AWS foundations OpenTofu module ([0a08721](https://github.com/do-now-io/socle/commit/0a087212dd7566e95bebdd0d52eeea3bf119439d))
* **aws:** the bootstrap node group, and the facts Cilium needs from the cluster ([5ad45b5](https://github.com/do-now-io/socle/commit/5ad45b585110c3ce78df2adb7a20480576599116)), closes [#32](https://github.com/do-now-io/socle/issues/32)
* **azure:** carry the pod range Cilium allocates from ([21bc1eb](https://github.com/do-now-io/socle/commit/21bc1ebdfda42023c67930b71559bbe28d98590a)), closes [#32](https://github.com/do-now-io/socle/issues/32)
* **azure:** foundations module — VNet, AKS Standard + NAP, identities ([5251c78](https://github.com/do-now-io/socle/commit/5251c780f86bbde2ff761c3bd523ad29be6c9293))
* **bootstrap:** install Cilium and CoreDNS before Flux, and Gateway API on every cloud ([945a6c3](https://github.com/do-now-io/socle/commit/945a6c3ecf27dc664573d91435e9d616fb322989)), closes [#32](https://github.com/do-now-io/socle/issues/32)
* **bootstrap:** the module — inputs only, Flux Operator renders the catalog ([fae5893](https://github.com/do-now-io/socle/commit/fae5893ff60f084d1815af892011f4093075ac14))
* **catalog:** grafana behind the shared Gateway ([4a2b111](https://github.com/do-now-io/socle/commit/4a2b11118be837a1e572408850886232dc210e0b)), closes [#43](https://github.com/do-now-io/socle/issues/43)
* **catalog:** kyverno and kyverno_policies — the admission layer, Enforce made native ([6eaedd9](https://github.com/do-now-io/socle/commit/6eaedd967fabdd65790cf43236bb334f6fc04dad))
* **catalog:** kyverno_policies judge the client's applications, never the socle's namespaces ([48bd663](https://github.com/do-now-io/socle/commit/48bd663250a359430d0ab8b3675b7ccc05137599))
* **catalog:** the argocd module — the client's GitOps layer ([4a1a25d](https://github.com/do-now-io/socle/commit/4a1a25d7f3de6d03ea5c8e255d5414f4182eb5ac))
* **catalog:** the artifact — hello module, one overlay per cloud, the cloud's colour ([256e416](https://github.com/do-now-io/socle/commit/256e4165997e32044fd00d06292e7039e7f2faf3))
* **catalog:** the crossplane module — the tooling for every module to carry its own cloud IAM ([faedb2f](https://github.com/do-now-io/socle/commit/faedb2fc5a86551a601b85889837e59949b54698))
* **catalog:** the external_dns module — DNS records in the cloud's own zone ([c1c4707](https://github.com/do-now-io/socle/commit/c1c470750ccaea36fdd9d42177ed1ddaeaaf9f28))
* **catalog:** the external_secrets module — Secrets from the cloud's secret manager, read-only by prefix ([bdb5bef](https://github.com/do-now-io/socle/commit/bdb5bef9832964c061d72411947e2a914b44891e))
* **catalog:** the grafana module — the one place to read ([d99cc47](https://github.com/do-now-io/socle/commit/d99cc47eefa1a9c39c63249f3ca0aa391119e27c)), closes [#43](https://github.com/do-now-io/socle/issues/43)
* **catalog:** the keda module — event-driven autoscaling, a role scoped to the services named ([cd31b4c](https://github.com/do-now-io/socle/commit/cd31b4ca19bd2fab2fc3231fa407d18521bf8419)), closes [#60](https://github.com/do-now-io/socle/issues/60)
* **catalog:** the otel_agent module — kubelet metrics from every node ([9afb1e6](https://github.com/do-now-io/socle/commit/9afb1e6304b3edea8d8f1ab531769ef16ad22276)), closes [#43](https://github.com/do-now-io/socle/issues/43)
* **catalog:** the otel_gateway module — cluster state, scraping and OTLP in ([9e92a3f](https://github.com/do-now-io/socle/commit/9e92a3ffcc4d79b2d89b53fcbe96d3dcb083f17e)), closes [#43](https://github.com/do-now-io/socle/issues/43)
* **catalog:** the reloader module — a workload rolled when what it reads changes, opt-in only ([b5fede1](https://github.com/do-now-io/socle/commit/b5fede1f5d5477295ee5eae82230e8fd2924e8c5))
* **catalog:** the victoria_logs module — the second signal ([ce5dc1f](https://github.com/do-now-io/socle/commit/ce5dc1f7e7cd03c5bcf351c3bbdfb95437fba79c)), closes [#43](https://github.com/do-now-io/socle/issues/43)
* **catalog:** the victoria_metrics module — the monitoring stack's metrics storage ([5f21fb0](https://github.com/do-now-io/socle/commit/5f21fb045b7c0863e5a1d371bf22d121cd08b628)), closes [#43](https://github.com/do-now-io/socle/issues/43)
* **catalog:** the victoria_traces module — the third signal, off by default ([aac0290](https://github.com/do-now-io/socle/commit/aac029024120fdeae4341d10392db2079f68d87f)), closes [#43](https://github.com/do-now-io/socle/issues/43)
* **ci:** publish and sign the artifact, prove it on floci, release it from the conventional commits ([a36212e](https://github.com/do-now-io/socle/commit/a36212e3a94b4641f16a5b2d63e6e7cc5027568f))
* **clusters:** the AWS root — one apply, one tfvars, one version ([dff54c7](https://github.com/do-now-io/socle/commit/dff54c70bbb249cbe707d1f0e5721f6b979686a5))
* **foundations:** a helm_kubernetes output on every cloud, stamped with the socle version ([91fe476](https://github.com/do-now-io/socle/commit/91fe4762e5945e3ad1bf8fa48f9c26f202e90925))
* **gcp:** state the Gateway API standard channel on the cluster ([ed05f55](https://github.com/do-now-io/socle/commit/ed05f55fc4aafe5b45ada012c2d33f56572548a0)), closes [#32](https://github.com/do-now-io/socle/issues/32)
* **gcp:** the GCP foundations OpenTofu module ([2347c8a](https://github.com/do-now-io/socle/commit/2347c8a99368d5099307fd1eefdc408dc05f1276))
* **registry:** publish the OpenTofu modules beside the socle, same version ([1ff1b20](https://github.com/do-now-io/socle/commit/1ff1b202fd674805b41d2eaec18e77f0ada96096))
* **registry:** the artifact lives at socle/flux-modules, the OpenTofu modules at socle/opentofu-modules ([7f8cef2](https://github.com/do-now-io/socle/commit/7f8cef2677483d016b28553993591a619ca6b395))
* **scaleway:** the Scaleway foundations OpenTofu module ([9f8dda5](https://github.com/do-now-io/socle/commit/9f8dda52f84c10d7d2e86231e5918034983ed51d))


### Bug Fixes

* **aws:** grant the applier cluster-admin explicitly, not by default ([d23fc54](https://github.com/do-now-io/socle/commit/d23fc546a2eb4d12c8294eec800b538f5966c331))
* **aws:** move the example back to eu-west-3 ([d6efd84](https://github.com/do-now-io/socle/commit/d6efd8465e78b94073c18ce6b547bf76e18e2968))
* **azure:** address the three Trivy findings on PR [#25](https://github.com/do-now-io/socle/issues/25) ([43f06a4](https://github.com/do-now-io/socle/commit/43f06a4fdb3ec810c4a91c728251633c7a856afd))
* **azure:** converge upgrade_settings drift, expose zones/vm_size overrides ([c3da35d](https://github.com/do-now-io/socle/commit/c3da35d7ae131aecac14cc0216dab89d529e08e6))
* **azure:** drop the cross-cloud comparison from the NAT Gateway note ([30fa72c](https://github.com/do-now-io/socle/commit/30fa72c76fe5ef65b57638bf7c63a03dc87baf27))
* **bootstrap:** the root Kustomization waits for the catalog's termination on uninstall ([200e537](https://github.com/do-now-io/socle/commit/200e537d7f0c7645eb32834e6d401753f534167f))
* **catalog:** argocd and crossplane values ConfigMaps carry the helm-controller watch label ([200e537](https://github.com/do-now-io/socle/commit/200e537d7f0c7645eb32834e6d401753f534167f))
* **catalog:** kyverno runs no cleanup controller, whose webhook outlived the uninstall ([0857e7c](https://github.com/do-now-io/socle/commit/0857e7c89cf6f57777c1604a1a7e8d6a857ddddf))
* **catalog:** the socle's defaults belong in the first valuesFrom, not inline ([271a187](https://github.com/do-now-io/socle/commit/271a1876fc64b32bcd28714cad6f47d6bf3cf35b))
* **ci:** one tag for both packages, and a promotion that can be re-run ([c2c8f8e](https://github.com/do-now-io/socle/commit/c2c8f8ebf870de745f7936f271159d1136bee400))
* **release:** pin the documented cosign identity to main, keep crane's stderr out of the digest ([7bf407d](https://github.com/do-now-io/socle/commit/7bf407ddf626b3cd79ac0620c84429f5897d51a2))
