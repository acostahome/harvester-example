<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_rancher2"></a> [rancher2](#requirement\_rancher2) | >= 13.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_rancher2"></a> [rancher2](#provider\_rancher2) | 13.1.4 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [rancher2_cloud_credential.harvester](https://registry.terraform.io/providers/rancher/rancher2/latest/docs/resources/cloud_credential) | resource |
| [rancher2_cluster_v2.demo](https://registry.terraform.io/providers/rancher/rancher2/latest/docs/resources/cluster_v2) | resource |
| [rancher2_machine_config_v2.demo](https://registry.terraform.io/providers/rancher/rancher2/latest/docs/resources/machine_config_v2) | resource |
| [rancher2_secret_v2.registryconfig-auth](https://registry.terraform.io/providers/rancher/rancher2/latest/docs/resources/secret_v2) | resource |
| [rancher2_cluster_v2.harvester](https://registry.terraform.io/providers/rancher/rancher2/latest/docs/data-sources/cluster_v2) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | n/a | `string` | `null` | no |
| <a name="input_cni"></a> [cni](#input\_cni) | n/a | `string` | `"cilium"` | no |
| <a name="input_cp_cpu"></a> [cp\_cpu](#input\_cp\_cpu) | n/a | `number` | `2` | no |
| <a name="input_cp_memory"></a> [cp\_memory](#input\_cp\_memory) | n/a | `number` | `4` | no |
| <a name="input_cp_nodes"></a> [cp\_nodes](#input\_cp\_nodes) | n/a | `number` | `1` | no |
| <a name="input_cp_root_disk_size"></a> [cp\_root\_disk\_size](#input\_cp\_root\_disk\_size) | n/a | `number` | `40` | no |
| <a name="input_hvst_cluster_id"></a> [hvst\_cluster\_id](#input\_hvst\_cluster\_id) | n/a | `string` | `null` | no |
| <a name="input_hvst_sa_kubeconfig"></a> [hvst\_sa\_kubeconfig](#input\_hvst\_sa\_kubeconfig) | n/a | `string` | `null` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | n/a | `string` | `null` | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | n/a | `string` | `null` | no |
| <a name="input_network_namespace"></a> [network\_namespace](#input\_network\_namespace) | n/a | `string` | `"harvester-public"` | no |
| <a name="input_psa_template"></a> [psa\_template](#input\_psa\_template) | n/a | `string` | `"rancher-restricted"` | no |
| <a name="input_registry_password"></a> [registry\_password](#input\_registry\_password) | n/a | `string` | `null` | no |
| <a name="input_registry_user"></a> [registry\_user](#input\_registry\_user) | n/a | `string` | `null` | no |
| <a name="input_ssh_user"></a> [ssh\_user](#input\_ssh\_user) | n/a | `string` | `null` | no |
| <a name="input_system_default_registry"></a> [system\_default\_registry](#input\_system\_default\_registry) | n/a | `string` | `null` | no |
| <a name="input_vm_namespace"></a> [vm\_namespace](#input\_vm\_namespace) | n/a | `string` | `null` | no |
| <a name="input_vmi_name"></a> [vmi\_name](#input\_vmi\_name) | n/a | `string` | `null` | no |
| <a name="input_vmi_namespace"></a> [vmi\_namespace](#input\_vmi\_namespace) | n/a | `string` | `"harvester-public"` | no |
| <a name="input_worker_nodes"></a> [worker\_nodes](#input\_worker\_nodes) | n/a | `number` | `0` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | n/a |
<!-- END_TF_DOCS -->