# Changelog

## [0.2.0](https://github.com/do-now-io/socle/compare/0.1.0...0.2.0) (2026-10-27)


### Features

* **aws:** the nodes' role as an instance profile, the boundary's one IAM exception, queues and rules for Crossplane ([8314f6b](https://github.com/do-now-io/socle/commit/8314f6b7b8223abc0e5c5033d25aaef30e08a01b))
* **bootstrap:** a default encrypted gp3 StorageClass on EKS, the EBS CSI driver scoped to its cluster ([437b735](https://github.com/do-now-io/socle/commit/437b73571e0fff738e6d0c3b604222d6dd53bdad)), closes [#95](https://github.com/do-now-io/socle/issues/95)
* **bootstrap:** argocd_image_updater in the catalog schema, its refusals and their tests ([c166443](https://github.com/do-now-io/socle/commit/c1664437fe646661967f308ef6f220cdc6188ee7))
* **catalog:** one monitoring module, and each module's own monitoring — kube-prometheus-stack's alerts on victoria-metrics-k8s-stack, awesome-prometheus-alerts' rules and the projects' dashboards per module ([3fde803](https://github.com/do-now-io/socle/commit/3fde80399308374ad508cc46208702f96f244d13))
* **catalog:** the argocd-image-updater template — its own namespace watching argocd, an ECR role scoped to the repositories named ([0486b0e](https://github.com/do-now-io/socle/commit/0486b0e78f1f9c9b4a73fb584a637ed32d37e9da))
* **catalog:** the karpenter module — nodes for the workloads on aws, its role and interruption queue through Crossplane ([c31e1a5](https://github.com/do-now-io/socle/commit/c31e1a5d2e0637dae380d782987787578cedf317))
* **charts:** an image tag may carry its digest, for Argo CD Image Updater's digest strategy ([e8f90fa](https://github.com/do-now-io/socle/commit/e8f90fa68738f94f822b5ba757aa7e9e05cea8c0))
* **charts:** both values schemas written from one set of definitions — cronjob's, and webapp's unchanged ([b5f05a4](https://github.com/do-now-io/socle/commit/b5f05a4123a6924bdc7d4325b31aabb6c13223b2))
* **charts:** cronjob's values contract — the schedule and the Job's limits, webapp's shared blocks in the same shape ([9397bae](https://github.com/do-now-io/socle/commit/9397bae887d8f6a661831befcafeaa02afb696ed))
* **charts:** podAnnotations on the cronjob chart's Job pods ([9a6be8d](https://github.com/do-now-io/socle/commit/9a6be8d08fcc32aa4b9f5fc389a9822ca35094fa))
* **charts:** socle-lib — the pod, the container and the restricted profile written once, with the objects both charts create ([2069353](https://github.com/do-now-io/socle/commit/206935372226b55d375711fae8c1f53d32dc41eb))
* **charts:** webapp's and cronjob's templates, thin over socle-lib — every helm-unittest suite green, every render valid under kubeconform and the restricted profile ([1a22ab4](https://github.com/do-now-io/socle/commit/1a22ab45ff85d27a1dea4b8799e036dd9faad310))
* **charts:** webapp's values contract — every key documented, required keys left empty, Kubernetes' own forms copied as is ([a47eecf](https://github.com/do-now-io/socle/commit/a47eecfdb5827dfa1d0d013389a290b3097e5090))
* **charts:** webapp's values schema — required keys, every key typed, unknown keys refused, the restricted profile not loosenable ([e99cfd1](https://github.com/do-now-io/socle/commit/e99cfd19cc77bdd2eff79972fce7d3e80944cc4c))
* **karpenter:** a public node pool beside the private one — egress through the Internet Gateway, nothing in from the internet ([7a24b3f](https://github.com/do-now-io/socle/commit/7a24b3fe227c3febaa4ae98bfd7a108f7445af0b))
* **site:** catalog.json, the graph's after edges per cloud, and the bricks filtered by cloud with the chart each module pins ([8814790](https://github.com/do-now-io/socle/commit/8814790d330f1a503218db84b3f28f03ce9e864d))
* the socle on GCP — GKE Autopilot at parity with AWS ([8372143](https://github.com/do-now-io/socle/commit/8372143471f1913faa2957974a0fb3ff94b0b9a2))


### Bug Fixes

* **aws:** a destroy leaves no log group behind — the flow logs' role cannot recreate its group, the control-plane group outlives EKS's last delivery ([bae9dac](https://github.com/do-now-io/socle/commit/bae9dac8659882b4d542bf9b6c2af2ceb446f1ca)), closes [#98](https://github.com/do-now-io/socle/issues/98)
* **bootstrap:** Flux built from the operator's embedded distribution, the health check inside Helm's timeout, cosign_identity anchored, owner a label value, flux_version as its message says ([48bc39a](https://github.com/do-now-io/socle/commit/48bc39ab8d65371038990c06ad57123d41986636))
* **catalog:** argocd-image-updater on the site and in the root job — the Argo mark, no destroyed phase ([84e2478](https://github.com/do-now-io/socle/commit/84e24789c37113cddd080f8918c247b0786ba729))
* **catalog:** argocd-image-updater passes yamllint — lines under 140, registries.conf quoted as one JMESPath key ([060ac45](https://github.com/do-now-io/socle/commit/060ac45b76eea86b489a7ef3c92b70a8ad98f660))
* **catalog:** argocd-image-updater's role reads image config blobs — newest-build needs ecr:GetDownloadUrlForLayer ([d273b68](https://github.com/do-now-io/socle/commit/d273b68bab2c73694c4d427e1be55082f5298001))
* **catalog:** kyverno-policies waits for kyverno's ResourceSet — it requires the engine, so the top-level dependsOn says so ([fb47f9c](https://github.com/do-now-io/socle/commit/fb47f9c2f73092a9bbbcfaf17e651117dfcd5bd5))
* **catalog:** on aws, a module's workload waits for a pod that has its Pod Identity credentials, not for the association being Ready ([408cd9b](https://github.com/do-now-io/socle/commit/408cd9b09856fb1395cb9c72319fe8666b27e5e9)), closes [#97](https://github.com/do-now-io/socle/issues/97)
* **catalog:** the Pod Identity check reads an optional &lt;module&gt;-aws Secret, the way round the injection an AWS-compatible endpoint needs ([78ec831](https://github.com/do-now-io/socle/commit/78ec831a14d2e37cbe83498028370b8a8eaa857c)), closes [#97](https://github.com/do-now-io/socle/issues/97)
* **charts:** the values schemas take a null tag or digest as unset, and the keys Helm adds for the library and globals ([b0cce22](https://github.com/do-now-io/socle/commit/b0cce2244a40f1c3d2581db2757d936a919e3c5e))
* **karpenter:** its health test runs on aws only, the one cloud that deploys the module ([14ddb4d](https://github.com/do-now-io/socle/commit/14ddb4d4bd7ee9f356d9caeb66ad465f0116b41c))
* **opentofu:** OpenTofu 1.13 or later everywhere — below it, anonymous tofu init of the public modules gets a 403 from ghcr ([83f0598](https://github.com/do-now-io/socle/commit/83f05988d3c3fa2b981ef39c5543b3255b5e1b98)), closes [#89](https://github.com/do-now-io/socle/issues/89)
* **site:** the banner names the last release when it predates the site — 0.1.0 was tagged before site/ existed ([0db70e7](https://github.com/do-now-io/socle/commit/0db70e7ed834be606eda59cc541bf3a46d2fa19d))

## 0.1.0 (2026-10-08)


### ⚠ BREAKING CHANGES

* **aws:** a cluster applied without cluster_log_types stops shipping control plane logs. Set it explicitly to keep them.
* **aws:** cluster_support_type is gone.
* **aws:** crossplane_service_account_namespace, crossplane_service_account_name and crossplane_policy_arns are gone, along with the crossplane_role_arn, ebs_csi_role_arn and crossplane_service_account_kubernetes_binding outputs.
* **aws:** take the four EKS add-ons out of the module

### Features

* **aws:** control plane logging is off by default, opt-in through cluster_log_types ([06bceb0](https://github.com/do-now-io/socle/commit/06bceb00cc7d125756cc5b3749ff62050a0a25d8)), closes [#80](https://github.com/do-now-io/socle/issues/80)
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
* **catalog:** alerting for the monitoring stack — vmalert and Alertmanager ([180d2af](https://github.com/do-now-io/socle/commit/180d2af3400553e51012f4bb5496a8c10d905da9)), closes [#59](https://github.com/do-now-io/socle/issues/59)
* **catalog:** grafana behind the shared Gateway ([4a2b111](https://github.com/do-now-io/socle/commit/4a2b11118be837a1e572408850886232dc210e0b)), closes [#43](https://github.com/do-now-io/socle/issues/43)
* **catalog:** kyverno and kyverno_policies — the admission layer, Enforce made native ([6eaedd9](https://github.com/do-now-io/socle/commit/6eaedd967fabdd65790cf43236bb334f6fc04dad))
* **catalog:** kyverno_policies judge the client's applications, never the socle's namespaces ([48bd663](https://github.com/do-now-io/socle/commit/48bd663250a359430d0ab8b3675b7ccc05137599))
* **catalog:** otel_agent's alert rule — a node filesystem nearly full ([78813e7](https://github.com/do-now-io/socle/commit/78813e7749d3001573b28cadf3ce6607379b6194))
* **catalog:** otel_gateway's alert rules — pods crash-looping or Pending, nodes not ready, Deployments missing replicas ([30aa992](https://github.com/do-now-io/socle/commit/30aa9926589ca8ee47bac980bb92855c6c91f0b9))
* **catalog:** the argocd module — the client's GitOps layer ([4a1a25d](https://github.com/do-now-io/socle/commit/4a1a25d7f3de6d03ea5c8e255d5414f4182eb5ac))
* **catalog:** the artifact — hello module, one overlay per cloud, the cloud's colour ([256e416](https://github.com/do-now-io/socle/commit/256e4165997e32044fd00d06292e7039e7f2faf3))
* **catalog:** the crossplane module — the tooling for every module to carry its own cloud IAM ([faedb2f](https://github.com/do-now-io/socle/commit/faedb2fc5a86551a601b85889837e59949b54698))
* **catalog:** the external_dns module — DNS records in the cloud's own zone ([c1c4707](https://github.com/do-now-io/socle/commit/c1c470750ccaea36fdd9d42177ed1ddaeaaf9f28))
* **catalog:** the external_secrets module — Secrets from the cloud's secret manager, read-only by prefix ([bdb5bef](https://github.com/do-now-io/socle/commit/bdb5bef9832964c061d72411947e2a914b44891e))
* **catalog:** the grafana module — the one place to read ([d99cc47](https://github.com/do-now-io/socle/commit/d99cc47eefa1a9c39c63249f3ca0aa391119e27c)), closes [#43](https://github.com/do-now-io/socle/issues/43)
* **catalog:** the keda module — event-driven autoscaling, a role scoped to the services named ([cd31b4c](https://github.com/do-now-io/socle/commit/cd31b4ca19bd2fab2fc3231fa407d18521bf8419)), closes [#60](https://github.com/do-now-io/socle/issues/60)
* **catalog:** the metrics_server module — the resource metrics API on aws ([ce89fb4](https://github.com/do-now-io/socle/commit/ce89fb49a95787fd49cf85b2c141431163333a77))
* **catalog:** the otel_agent module — kubelet metrics from every node ([9afb1e6](https://github.com/do-now-io/socle/commit/9afb1e6304b3edea8d8f1ab531769ef16ad22276)), closes [#43](https://github.com/do-now-io/socle/issues/43)
* **catalog:** the otel_gateway module — cluster state, scraping and OTLP in ([9e92a3f](https://github.com/do-now-io/socle/commit/9e92a3ffcc4d79b2d89b53fcbe96d3dcb083f17e)), closes [#43](https://github.com/do-now-io/socle/issues/43)
* **catalog:** the reloader module — a workload rolled when what it reads changes, opt-in only ([b5fede1](https://github.com/do-now-io/socle/commit/b5fede1f5d5477295ee5eae82230e8fd2924e8c5))
* **catalog:** the velero module — backups the application chooses by two labels, restored with their data ([a3e5977](https://github.com/do-now-io/socle/commit/a3e597746a0c1ed999374a34a1cc65b0bd544d4b))
* **catalog:** the victoria_logs module — the second signal ([ce5dc1f](https://github.com/do-now-io/socle/commit/ce5dc1f7e7cd03c5bcf351c3bbdfb95437fba79c)), closes [#43](https://github.com/do-now-io/socle/issues/43)
* **catalog:** the victoria_metrics module — the monitoring stack's metrics storage ([5f21fb0](https://github.com/do-now-io/socle/commit/5f21fb045b7c0863e5a1d371bf22d121cd08b628)), closes [#43](https://github.com/do-now-io/socle/issues/43)
* **catalog:** the victoria_traces module — the third signal, off by default ([aac0290](https://github.com/do-now-io/socle/commit/aac029024120fdeae4341d10392db2079f68d87f)), closes [#43](https://github.com/do-now-io/socle/issues/43)
* **catalog:** victoria_metrics' alert rules, and Grafana lists the socle's rules ([292680e](https://github.com/do-now-io/socle/commit/292680e0e3a3be76ac87fd7771c8cc1e23c91f4b))
* **ci:** publish and sign the artifact, prove it on floci, release it from the conventional commits ([a36212e](https://github.com/do-now-io/socle/commit/a36212e3a94b4641f16a5b2d63e6e7cc5027568f))
* **clusters:** the AWS root — one apply, one tfvars, one version ([dff54c7](https://github.com/do-now-io/socle/commit/dff54c70bbb249cbe707d1f0e5721f6b979686a5))
* **crossplane:** buckets a module owns — provider-aws-s3, a bucket grant with no delete, the account and the snapshot controller in the inputs ([35ca8b8](https://github.com/do-now-io/socle/commit/35ca8b8f317889f1fa2d08cd00580aef8a41195a))
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
* **catalog:** the AWS providers run as a ServiceAccount the module creates, so no revision owns it and none takes it back ([ffe6574](https://github.com/do-now-io/socle/commit/ffe6574411920e07c1b8db4692866d2699392103)), closes [#80](https://github.com/do-now-io/socle/issues/80)
* **catalog:** the socle's defaults belong in the first valuesFrom, not inline ([271a187](https://github.com/do-now-io/socle/commit/271a1876fc64b32bcd28714cad6f47d6bf3cf35b))
* **catalog:** velero's runbook deletes the Restore once checked — its finalizer otherwise holds the namespace when the module goes ([a1768a1](https://github.com/do-now-io/socle/commit/a1768a16f5d2c23bc0afe4572fa79e3229380c63))
* **ci:** one tag for both packages, and a promotion that can be re-run ([c2c8f8e](https://github.com/do-now-io/socle/commit/c2c8f8ebf870de745f7936f271159d1136bee400))
* **crossplane:** a bucket's tags go through S3 Control — the grant, floci's services, and the tests wait for every CRD they assert ([c6f3a6d](https://github.com/do-now-io/socle/commit/c6f3a6dce77882aea7c3888c735dfa1acca8c989))
* **release:** pin the documented cosign identity to main, keep crane's stderr out of the digest ([7bf407d](https://github.com/do-now-io/socle/commit/7bf407ddf626b3cd79ac0620c84429f5897d51a2))
