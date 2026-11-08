# AWS Milestone 1: account validation and VPC plan

**Inspection date:** 2026-11-08

**Target region:** `us-east-1` (N. Virginia)

**Scope:** Read-only AWS inspection and VPC/Terraform planning. No AWS resources were changed or provisioned.

## Inspection findings

- The `devops-practice` AWS CLI profile resolves to an IAM user. The configured profile region is `us-east-1`; Terraform CLI is v1.11.1 on Apple Silicon.
- The caller has `AdministratorAccess` and `AmazonEC2FullAccess` attached. IAM policy simulation allowed the required VPC describe/create, route, NAT, EIP, and tagging actions. There is no permissions boundary or user inline policy. Use a dedicated, narrowly-scoped deployment role with short-lived credentials for future Terraform operations; do not use this administrator identity for routine infrastructure automation.
- The account/region contains one default VPC, `172.31.0.0/16`, with six default `/20` subnets across `us-east-1a` through `us-east-1f`, a main route table with a default route through its Internet Gateway, and the default network ACL. No NAT Gateway or allocated Elastic IP was found.
- The proposed `10.0.0.0/16` does not overlap the VPCs and subnets observed in this account/region. This check cannot determine whether it overlaps a corporate, VPN, peered, or other network that is not connected to this account.
- Reported quotas: 5 VPCs per region (one currently present), 200 subnets per VPC, 5 NAT Gateways per AZ, and 5 Elastic IP addresses per region (none currently allocated).
- The current `main` branch contains Terraform modules under `terraform/`. There is no state backend configuration. The networking module currently enables one NAT Gateway per AZ, defaults to three AZs, generates subnet ranges different from the requested ranges, and the region default is `ap-south-1`.

Credentials were not read, printed, or added to the repository. The Terraform configuration was inspected from Git; no `terraform init`, `apply`, or AWS configuration change was performed.

## Proposed address plan

| Subnet | CIDR | Availability Zone | Purpose |
| --- | --- | --- | --- |
| Public AZ-A | `10.0.1.0/24` | First selected standard AZ | Future internet-facing load balancer and NAT (if enabled) |
| Public AZ-B | `10.0.2.0/24` | Second selected standard AZ | Future internet-facing load balancer and NAT (if enabled) |
| Private AZ-A | `10.0.11.0/24` | Same as Public AZ-A | EKS managed nodes and application workloads |
| Private AZ-B | `10.0.12.0/24` | Same as Public AZ-B | EKS managed nodes and application workloads |

The VPC CIDR is `10.0.0.0/16`. Use two standard, available AZs selected by Terraform and pin the resulting AZ names in the deployment inputs for reproducible plans. Validate the CIDR map and all connected-network ranges before any apply.

## Routing and security design

- Attach one Internet Gateway to the new VPC.
- Associate both public subnets with a public route table containing the VPC-local route and `0.0.0.0/0` to the Internet Gateway. Keep automatic public IPv4 assignment disabled by default; public load-balancer addresses are managed by that service.
- Keep EKS nodes and application workloads in private subnets without public IPs. Do not add an Internet Gateway route to private route tables.
- If NAT is explicitly enabled, use one private route table per AZ and route each private subnet through the NAT Gateway in the same AZ. A single-NAT development option can instead route both private subnets through one gateway, with reduced egress resilience and possible cross-AZ transfer charges.
- Restrict the future EKS API endpoint to private access or explicitly trusted source CIDRs. Use security groups to allow load-balancer ingress only on required application ports and to restrict node ingress to cluster and workload paths. Avoid broad `0.0.0.0/0` node or control-plane rules. Keep the default network ACL unless a concrete requirement calls for custom stateless filtering.
- Tag public subnets for external load balancers and private subnets for internal load balancers when the EKS load-balancer integration is introduced.

## NAT and monthly network estimate

The figures below use 730 hours per month and current published US East (N. Virginia) public IPv4/NAT rates. They exclude taxes, internet data transfer out, cross-AZ transfer, and traffic-dependent charges beyond the stated NAT processing volume.

| Component | One NAT Gateway | Two NAT Gateways |
| --- | ---: | ---: |
| NAT Gateway hours (`$0.045/hour`) | `$32.85` | `$65.70` |
| One public IPv4 per NAT (`$0.005/hour`) | `$3.65` | `$7.30` |
| Fixed monthly baseline | **`$36.50`** | **`$73.00`** |
| NAT processing at 100 GB (`$0.045/GB`) | `$4.50` | `$4.50` |
| Example total at 100 GB | **`$41.00`** | **`$77.50`** |

The VPC, subnets, route tables, and Internet Gateway have no component-hour charge. NAT Gateway charges accrue while provisioned, even when traffic is low. A shared NAT Gateway can add cross-AZ transfer costs for traffic from the other AZ. Internet egress and public IPv4 addresses attached to future resources (for example, a public load balancer) are billed separately. Interface VPC endpoints, if used instead of NAT for AWS APIs, have hourly and data-processing costs; CloudWatch Logs or VPC Flow Logs can also add charges.

**Recommendation:** keep NAT disabled by default in Terraform. For a development deployment that requires outbound access from private nodes, explicitly choose one NAT Gateway and accept the AZ dependency/cross-AZ tradeoff. Choose one NAT Gateway per AZ for production availability and local egress. For a no-NAT environment, first mirror required images to ECR and cost the required VPC endpoints; private nodes otherwise lack general outbound access. Do not create NAT automatically.

## Existing Terraform scaffold and implementation plan

The existing networking module uses `terraform-aws-modules/vpc/aws` (`~> 5.0`) and currently calculates public subnet indexes from 0 and private indexes from 10. For the requested layout, make subnet CIDRs explicit (or use public indexes 1/2 and private indexes 11/12) rather than relying on the current offsets. Change the region input default from `ap-south-1` to `us-east-1`, and set the environment to two AZs.

Before implementation, revise the networking module to:

1. Accept the approved VPC CIDR, two AZ names, and explicit public/private CIDR lists.
2. Add a validated NAT mode such as `disabled`, `single`, or `per_az`, with `disabled` as the safe default. Derive NAT routes and NAT resources only from an explicit mode.
3. Keep VPC DNS support/hostnames enabled, add public/private subnet load-balancer role tags, and keep private nodes unaddressed by public IPv4.
4. Add outputs for VPC ID, subnet IDs, route-table IDs, and NAT mode/IDs so later EKS modules can consume the network without duplicating resources.
5. Configure and document a remote Terraform state backend with encryption, versioning, and state locking before the first apply. Do not put credentials or environment-specific secrets in `.tfvars`; use the AWS profile/role chain and non-secret inputs.
6. Validate with `terraform fmt -check`, `terraform validate`, a reviewed `terraform plan`, CIDR/route assertions, and a secret scan. Inspect the plan for unintended changes to the existing default VPC. Provisioning remains a separate explicit approval step.

The existing EKS module is outside this VPC milestone. It currently selects `t3.large` nodes with three desired instances and allows public API access subject to a CIDR input; those choices and their cost/security implications should be reviewed in the EKS milestone.

## Pricing and design references

- [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/) — NAT Gateway hourly/data-processing charges and public IPv4 address rates.
- [NAT Gateway pricing guidance](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html) — hourly/data processing and same-AZ routing guidance.
- [Internet Gateway basics](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html) — no Internet Gateway charge; normal data transfer charges still apply.
- [NAT Gateway basics](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html) — a NAT Gateway is AZ-scoped; use one per AZ for resilient local egress.
- [EC2 data transfer pricing](https://aws.amazon.com/ec2/pricing/on-demand/) — cross-AZ transfer is billed by direction.
