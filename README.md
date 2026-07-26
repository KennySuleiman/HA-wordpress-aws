# HA-wordpress-aws
High avalability wordpress-aws
# Highly Available WordPress on AWS

A production-style, highly available WordPress deployment on AWS, built entirely with Terraform, Docker, and GitHub Actions — with automated backups, monitoring, and CI/CD.

**Live status of this build:** Infrastructure is destroyed between work sessions to control cost (see [Cost Notes](#cost-notes--why-things-get-torn-down)). Everything documented below has been deployed and verified live at least once.

---

## Architecture

```
                              Route 53 (DNS)
                                    │
                                    ▼
                    Application Load Balancer (public subnets, 2 AZs)
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                                 ▼
            EC2 (AZ-a, private)               EC2 (AZ-b, private)
            Docker: Nginx + WordPress          Docker: Nginx + WordPress
                    │                                 │
                    └───────────────┬───────────────┘
                                     ▼
                    ┌────────────────┴────────────────┐
                    ▼                                   ▼
              EFS (shared wp-content)          RDS MySQL (Multi-AZ)
                    │                                   │
                    ▼                                   ▼
              S3 (backups, app config)         CloudWatch (logs, metrics, alarms)

  Outbound internet for private subnets: t3.micro NAT instance (not a
  managed NAT Gateway — see Cost Notes)
```

### Why each component is there

| Component | Purpose |
|---|---|
| **Route 53** | DNS + health-check-aware failover routing to the ALB (code complete, dormant until a domain is registered — see [Phase 8](#phase-8--route-53--lets-encrypt-ssl-deferred)) |
| **Application Load Balancer** | Public entry point; health-checks `/health` on each instance and only routes to healthy targets |
| **EC2 in private subnets, Auto Scaling Group (min 2)** | Runs the app; ASG replaces any instance that fails ALB health checks automatically |
| **EFS** | Shared `wp-content` (themes, plugins, uploads) so every instance serves identical content |
| **RDS MySQL, Multi-AZ** | Synchronously replicated standby in a second AZ; automatic failover (~60–120s) on primary failure |
| **NAT instance (t3.micro)** | Outbound-only internet access for private-subnet instances, chosen over a managed NAT Gateway for cost (see below) |
| **S3** | Backup storage (30-day lifecycle) and CI/CD deployment package storage |
| **CloudWatch** | Agent-shipped logs (bootstrap, backup, system, container logs) + custom OS metrics (memory, disk) + 6 alarms + a dashboard |
| **GitHub Actions (OIDC)** | CI/CD: packages `wp-content` changes, deploys via SSM to every running instance, health-checks, rolls back on failure |

### Security model

- EC2 instances have **no SSH access at all** — management is exclusively via **AWS Systems Manager Session Manager**, which requires no open inbound port and logs every session.
- EC2 sits in **private subnets** with security-group rules that only accept 80/443 from the ALB's security group — not from the internet directly, and not from arbitrary VPC CIDR ranges.
- RDS and EFS are reachable **only from the EC2 security group**, on their respective ports (3306, 2049).
- DB credentials are generated with Terraform's `random_password` and stored in **AWS Secrets Manager** — never hardcoded, never committed, and not even exposed via Terraform outputs (EC2 reads them directly via IAM at boot).
- The EC2 IAM role is scoped to exactly what it needs (SSM, CloudWatch agent, read one specific secret, read/write one specific S3 bucket) — no wildcard `*` resource policies except where AWS APIs genuinely don't support resource-level scoping (e.g. `ec2:DescribeInstances`).
- The GitHub Actions role uses **OIDC federation**, not long-lived AWS access keys — and its trust policy is scoped to this specific repo and the `main` branch only.
- IMDSv2 is enforced (`http_tokens = "required"`) on the launch template to close a known SSRF-to-credential-theft path.

---

## Repository structure

```
project-root/
├── terraform/
│   ├── backend.tf, providers.tf, variables.tf, outputs.tf
│   ├── vpc.tf              # VPC, subnets, NAT instance
│   ├── security-groups.tf  # ALB / EC2 / RDS / EFS security groups
│   ├── rds.tf               # RDS MySQL Multi-AZ + Secrets Manager
│   ├── efs.tf                # EFS + access point
│   ├── iam.tf                # EC2 IAM role and policies
│   ├── s3.tf                  # Backup bucket
│   ├── ec2.tf                 # Launch template, ASG, S3 config uploads
│   ├── alb.tf                  # ALB, target group, listener
│   ├── cloudwatch.tf           # Log groups, alarms, SNS, dashboard
│   ├── route53.tf               # DNS + failover (dormant until domain set)
│   └── github-oidc.tf            # GitHub Actions OIDC IAM role (dormant until repo set)
├── docker/
│   ├── docker-compose.yml   # WordPress (php-fpm) + Nginx
│   └── nginx/nginx.conf
├── scripts/
│   ├── bootstrap.sh    # EC2 user-data: installs everything, starts the stack
│   ├── backup.sh         # DB dump + wp-content archive → S3, cron'd daily at 03:00
│   ├── restore.sh          # Restore DB and/or files from an S3 backup
│   ├── deploy.sh             # CI/CD: sync new themes/plugins to EFS, with rollback point
│   ├── rollback.sh             # CI/CD: restore the previous deploy's backup
│   └── ssl-renewal.sh           # Let's Encrypt via DNS-01 (dormant until domain set)
├── .github/workflows/deploy.yml   # CI/CD pipeline
├── monitoring/cloudwatch-config.json
├── wp-content/{themes,plugins}/    # CI/CD watches this path
└── docs/
    ├── failover-test-results.md
    └── README.md (this file)
```

---

## What's built and verified

| Phase | Scope | Status |
|---|---|---|
| 0 | Remote Terraform state (S3 + DynamoDB lock) | ✅ Verified |
| 1 | VPC — public/private/data subnets across 2 AZs, NAT instance | ✅ Verified |
| 2 | Security groups, SSM-only management (no SSH) | ✅ Verified |
| 3 | RDS MySQL Multi-AZ, Secrets Manager credentials | ✅ Verified |
| 4 | EFS shared storage with access point | ✅ Verified |
| 5 | EC2 IAM role (least privilege), S3 backup bucket | ✅ Verified |
| 6 | Launch template, Docker Compose, Nginx reverse proxy, bootstrap automation | ✅ Verified |
| 7 | ALB + Auto Scaling Group — WordPress reachable end-to-end | ✅ Verified |
| 8 | Route 53 + Let's Encrypt SSL (DNS-01 challenge) | 🟡 Code complete, **dormant** — needs a registered domain to activate |
| 9 | Automated backups (DB + files), S3 lifecycle policy, restore script | ✅ Verified live |
| 10 | CloudWatch agent, log groups, custom metrics, 6 alarms, SNS, dashboard | ✅ Verified live |
| 11 | CI/CD via GitHub Actions (OIDC, SSM deploy, health check, rollback) | ✅ Verified live — full green pipeline run |
| HA | Failover test: hard instance termination → automatic recovery | ✅ Verified, see [`docs/failover-test-results.md`](./failover-test-results.md) |

### High availability, demonstrated

A running instance was force-terminated (`aws ec2 terminate-instances`) while a continuous health-check loop polled the site every 2 seconds. Result:
- ~30 seconds of `504` responses while the ALB detected the loss and routed around it
- The surviving instance kept serving traffic throughout
- The Auto Scaling Group launched a replacement automatically, with zero manual intervention
- Target group returned to 2/2 healthy within ~3 minutes

Full timestamped log in [`docs/failover-test-results.md`](./failover-test-results.md).

### CI/CD, demonstrated

A `workflow_dispatch`-triggered run completed the full pipeline in 43 seconds: package `wp-content` → upload to S3 → discover running instances → deploy via SSM Run Command → ALB health check gate. Verified on the instance that `deploy.sh` created a timestamped rollback point before applying changes.

---

## Debugging log — real infrastructure issues found and fixed

This project surfaced several genuine, non-obvious AWS/Amazon Linux 2023 issues. Documenting them here both as a troubleshooting reference and because working through them was a meaningful part of the learning process.

1. **NAT instance missing `iptables`** — Amazon Linux 2023 doesn't ship `iptables` by default (unlike AL2). The NAT instance's `user_data` script silently failed on the `iptables -t nat -A POSTROUTING ...` line, so no MASQUERADE rule was ever created — private subnets had zero outbound internet, cascading into failed SSM registration, failed Docker pulls, and failed health checks. **Fix:** `dnf install -y iptables` before use, plus adding `user_data_replace_on_change = true` (without this, the AWS provider silently updates Terraform *state* on a `user_data` diff without actually recreating the running EC2 instance — a real provider-behavior gotcha).

2. **Root EBS volume too small for the AMI's snapshot** — an initial fix of `volume_size = 20` failed with `Volume of size 20GB is smaller than snapshot 'snap-...', expect size >= 30GB`. The current AL2023 AMI's source snapshot is 30GB; AWS requires the root volume to be at least that size. **Fix:** raised to `volume_size = 30`.

3. **Missing `cronie` package** — the daily backup cron job silently failed to install because `/etc/cron.d/` doesn't exist without the `cronie` package on a minimal AL2023 image. **Fix:** added `cronie` to the initial `dnf install` line in `bootstrap.sh`.

4. **`mysqldump` not available inside the WordPress container** — the official `wordpress:...-fpm` image ships PHP's MySQL extensions but not the MySQL client CLI tools. **Fix:** run `mysqldump`/`mysql` via a disposable `mysql:8.0` container (`docker run --rm --network wordpress_wp-net mysql:8.0 ...`) attached to the same Docker network, rather than relying on tooling inside the app container.

5. **AMI filter unintentionally matching the "minimal" AL2023 variant** — the wildcard filter `al2023-ami-*-x86_64` matched both the standard AMI and `al2023-ami-minimal-...`, and AWS began returning the minimal variant as "most recent." The minimal AMI does not ship the SSM agent, so instances had working networking and served traffic normally, but never registered with SSM — breaking both manual management and the CI/CD pipeline's SSM-based deploy step. **Fix:** tightened the filter to `al2023-ami-2023.*-x86_64`, which only matches the standard-variant naming convention.

6. **GitHub Actions IAM role missing `elasticloadbalancing:DescribeLoadBalancers`** — the CI/CD workflow's health-check step needed to look up the ALB's DNS name, but the OIDC role's policy only covered S3, SSM, and EC2 describe actions. **Fix:** added the missing statement, scoped as a describe/read action (AWS doesn't support resource-level scoping for it).

7. **WordPress core vs. `wp-content` volume sharing** — early on, Nginx returned `403 Forbidden` because the Docker Compose file only shared `wp-content` between the `wordpress` and `nginx` containers; WordPress core files (`index.php`, `wp-admin/`, etc.) were generated inside the `wordpress` container's own filesystem and invisible to `nginx`. **Fix:** introduced a named Docker volume (`wordpress_core`) mounted at `/var/www/html` in both containers, with EFS mounted specifically at the nested `wp-content` path inside it — core files are per-instance/ephemeral (regenerated automatically, no need to share or persist them), while `wp-content` remains the one directory genuinely shared across the fleet via EFS.

---

## Cost notes — why things get torn down

This project deliberately avoids a managed **NAT Gateway** (~$32–65/month) in favor of a **t3.micro NAT instance**, which is free-tier eligible if usage stays within the account's combined 750 free t3.micro-hours/month. Because the pattern used here is "build → test → demo → `terraform destroy`" across short sessions rather than leaving the stack running continuously, actual t3.micro usage stays well within free tier — three t3.micro instances (NAT + 2 WordPress) running 24/7 would exhaust the free pool in about 10 days, so the discipline of destroying between sessions is what keeps this at effectively $0 compute cost.

**RDS Multi-AZ is the one component with no free-tier workaround** — the free tier's 750 `db.t3.micro` hours explicitly excludes Multi-AZ, since it runs two instances. Left running continuously, this is roughly $25–30/month; this is the main reason for tearing down between sessions rather than a cost-optimization nicety.

Resources that made `terraform destroy` unreliable without explicit handling, and how each was addressed:
- **RDS** — `skip_final_snapshot = true`, `deletion_protection = false`
- **Secrets Manager** — `recovery_window_in_days = 0` (skips the normal 7–30 day soft-delete hold)
- **S3 backup bucket** — `force_destroy = true` (allows destroy even with backup objects present)
- **NAT instance's Elastic IP** — tied to the instance's lifecycle via `depends_on`, released automatically on destroy

### Recommended production changes (not done here, for cost reasons)
- Replace the NAT instance with a managed NAT Gateway (or one per AZ for full fault isolation)
- Increase RDS storage/instance class for real workloads
- Keep infrastructure running continuously with proper environment separation (dev/staging/prod) rather than destroy/rebuild cycles

---

## Deployment guide

### Prerequisites
- AWS account with programmatic access configured (`aws configure`)
- Terraform >= 1.9
- Docker (for local development only — not required for AWS deployment)
- Session Manager plugin for the AWS CLI (`session-manager-plugin`) for SSM access

### First-time setup
```bash
git clone <this-repo>
cd HA-wordpress-aws/terraform

# One-time: create the S3 bucket + DynamoDB table for remote state (see backend.tf
# for the exact bucket name to use, or create your own and update backend.tf)

terraform init
terraform plan
terraform apply
```

RDS Multi-AZ provisioning takes 10–15 minutes; everything else is fast. Once applied:

```bash
terraform output alb_dns_name
curl -I http://$(terraform output -raw alb_dns_name)/
```

A `302 Found` redirecting to `/wp-admin/install.php` confirms the stack is healthy end-to-end.

### Tearing down
```bash
terraform destroy
```

Verify no billable resources remain:
```bash
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId'
aws ec2 describe-addresses --query 'Addresses[?AssociationId==`null`]'
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier'
aws efs describe-file-systems --query 'FileSystems[].FileSystemId'
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'
aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[].AutoScalingGroupName'
```
All should return `[]`.

### Enabling optional features
- **SSL / custom domain (Phase 8):** register a domain, set `domain_name` and `letsencrypt_email` in `terraform.tfvars`, `terraform apply`, then run `ssl-renewal.sh` once via SSM to issue the first certificate.
- **Alarm email notifications:** set `alarm_email` in `terraform.tfvars`, `terraform apply`, then confirm the SNS subscription email.
- **CI/CD:** set `github_repo` in `terraform.tfvars`, `terraform apply`, copy `terraform output github_actions_role_arn` into a GitHub repo secret named `AWS_DEPLOY_ROLE_ARN`.

---

## Backup and recovery

- **Automated:** `backup.sh` runs daily at 03:00 via cron on one instance (a lock file prevents both ASG instances from running it simultaneously), dumping the database and archiving `wp-content`, uploading both to S3 with a 30-day lifecycle expiration.
- **Manual trigger:** `sudo /opt/wordpress/scripts/backup.sh <bucket> <db-secret-arn> <region>` via SSM.
- **Restore:** `sudo /opt/wordpress/scripts/restore.sh <bucket> <db-secret-arn> <region> <db-backup-key|skip> <files-backup-key|skip>` — includes a 10-second abort window before making destructive changes, and stages file restores in a temp directory before syncing into the live EFS mount to avoid serving a partially-restored directory tree.

## Monitoring and alerting

Dashboard: `terraform output cloudwatch_dashboard_url`

| Alarm | Trigger |
|---|---|
| ASG below desired capacity | Fewer than 2 in-service instances for 2 minutes |
| RDS high CPU | >80% average CPU for 15 minutes |
| RDS low storage | Free storage below 2GB |
| ALB 5xx errors | >10 target 5xx responses in 2 minutes |
| High memory | >85% average for 15 minutes (custom metric via CloudWatch agent) |
| High disk | >80% average for 10 minutes (custom metric — added directly in response to the EBS-sizing incident above) |

## CI/CD pipeline

Trigger: push to `main` touching `wp-content/themes/**` or `wp-content/plugins/**`, or manual `workflow_dispatch`.

Flow: package → upload to S3 → discover running instances → deploy via SSM Run Command (each instance backs up its current state before applying changes) → ALB health check → automatic rollback via SSM if the health check fails.

---

## Known limitations / further improvements

- Route 53 + SSL is code-complete but dormant pending domain registration
- Restore path (`restore.sh`) is written and reviewed but not yet exercised in a live test — worth doing deliberately before relying on it
- Rollback path in the CI/CD pipeline is wired in but hasn't been exercised via a genuine failing deployment
- Docker container logs are shipped to CloudWatch as raw JSON-wrapped lines rather than cleanly parsed/separated nginx access vs. error logs
- Single NAT instance (not per-AZ) is a deliberate cost tradeoff — see [Cost Notes](#cost-notes--why-things-get-torn-down)
- No multi-region deployment, blue-green deployment, or Terratest coverage (listed as bonus items in the original spec)
