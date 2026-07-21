# ---------- Trust policy: only EC2 can assume this role ----------
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

# ---------- SSM Session Manager access (no SSH, per Phase 2 decision) ----------
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ---------- CloudWatch agent: ship logs/metrics from the instance ----------
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ---------- Scoped read access to only the DB credentials secret ----------
data "aws_iam_policy_document" "secrets_read" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db_credentials.arn]
  }
}

resource "aws_iam_role_policy" "secrets_read" {
  name   = "${var.project_name}-secrets-read"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.secrets_read.json
}

# ---------- Scoped S3 access: only the backup bucket, only needed actions ----------
data "aws_iam_policy_document" "s3_backups" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.backups.arn,
      "${aws_s3_bucket.backups.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "s3_backups" {
  name   = "${var.project_name}-s3-backups"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.s3_backups.json
}

# ---------- Instance profile: what EC2 actually attaches to ----------
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ---------- Route 53 DNS-01 permissions for Let's Encrypt (only created once domain_name is set) ----------
data "aws_iam_policy_document" "route53_dns01" {
  count = local.create_dns ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.main[0].zone_id}"]
  }

  statement {
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets"]
    resources = ["*"] # these two actions don't support resource-level scoping
  }
}

resource "aws_iam_role_policy" "route53_dns01" {
  count  = local.create_dns ? 1 : 0
  name   = "${var.project_name}-route53-dns01"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.route53_dns01[0].json
}
