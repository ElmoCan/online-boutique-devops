# Terraform: AWS networking and platform scaffold

This configuration targets `us-east-1`. The networking module creates a new
VPC and does not look up or manage the account's default VPC.

## VPC layout

| Subnet | CIDR | Intended use |
| --- | --- | --- |
| Public AZ A | `10.0.1.0/24` | Internet-facing load balancers; NAT when explicitly enabled |
| Public AZ B | `10.0.2.0/24` | Internet-facing load balancers; NAT when explicitly enabled |
| Private AZ A | `10.0.11.0/24` | EKS nodes and workloads |
| Private AZ B | `10.0.12.0/24` | EKS nodes and workloads |

Terraform selects the first two available AZs returned by AWS in the configured
region. Review and pin AZ names in environment-specific inputs if repeatability
across accounts is required. Public IPv4 assignment on subnet launch is
disabled. EKS managed nodes explicitly use private subnet IDs and disable
public IP association.

Public subnets have `kubernetes.io/role/elb=1`; private subnets have
`kubernetes.io/role/internal-elb=1`. Both carry the cluster discovery tag
`kubernetes.io/cluster/online-boutique-dev=shared` for future AWS Load Balancer
Controller discovery. The cluster name follows `project_name-environment`.

## Inputs

| Variable | Default | Purpose |
| --- | --- | --- |
| `aws_region` | `us-east-1` | AWS region |
| `project_name` | `online-boutique` | Resource name prefix |
| `environment` | `dev` | Environment suffix |
| `vpc_cidr` | `10.0.0.0/16` | New VPC IPv4 range |
| `availability_zones` | `2` | Fixed to two by validation |
| `nat_gateway_mode` | `disabled` | `disabled`, `single`, or `per_az` |
| `eks_cluster_version` | Required | EKS version, selected before EKS deployment |
| `cluster_endpoint_public_access_cidrs` | Required | Trusted client CIDRs; `0.0.0.0/0` is rejected |

`github_owner` and `github_repository` default to placeholders for the separate
GitHub OIDC module and must be set before using that module. Do not commit
environment-specific `.tfvars` files or credentials.

## Outputs

The root module exposes the VPC ID, public/private subnet IDs, public/private
route table IDs, NAT Gateway IDs, ECR repository URL and EKS cluster name.
When NAT is disabled, `nat_gateway_ids` is an empty list.

## NAT behavior and cost

- `disabled` (default): no NAT Gateway, Elastic IP, or private default egress
  route is created. Private nodes cannot reach arbitrary internet destinations.
- `single`: one NAT Gateway in the first public subnet. It costs less but creates
  a single-AZ egress dependency and may incur cross-AZ transfer charges.
- `per_az`: one NAT Gateway per AZ and same-AZ private routing for better egress
  availability, at roughly twice the fixed NAT cost.

At 730 hours/month in `us-east-1`, published rates imply approximately
`$36.50/month` fixed for one NAT Gateway (gateway hours plus one public IPv4), or
`$73/month` for two, before data processing and transfer. NAT processing is
additional (the plan document uses 100 GB as a `$4.50` example). The VPC,
subnets, route tables, and Internet Gateway have no hourly charge. These are
estimates; recheck AWS pricing before enabling NAT. The default configuration
creates no NAT Gateway or Elastic IP.

## State and prerequisites

There is deliberately no remote backend block. This repository creates no S3
bucket, lock table, or other state infrastructure. Terraform's default local
state is suitable only for an individual sandbox; keep `terraform.tfstate` and
backups out of Git (the repository `.gitignore` excludes them). Before shared or
production use, choose and approve a remote state design with encryption,
versioning, access controls, and locking, and provision it in a separate
reviewed step.

Prerequisites: Terraform `>=1.6`, AWS CLI v2, AWS credentials from a profile or
short-lived role, and permission to read availability zones and plan the
resources. The provider region defaults to `us-east-1`. Check CIDR ranges against
all connected networks, including VPNs and peering, before deployment.

## Safe local validation

From this directory:

```sh
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform plan -refresh=false -target=module.networking
```

The plan command is scoped to networking and is not a full-platform deployment
plan. Review every plan and its region, CIDRs, routes, NAT resources, and state
before any separately approved apply. This project change does not authorize or
perform `terraform apply`.
