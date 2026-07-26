variable "github_repo" {
  description = "GitHub repo in 'owner/repo' format, for OIDC trust scoping"
  type        = string
  default     = ""
}

locals {
  create_oidc = var.github_repo != ""
}

resource "aws_iam_openid_connect_provider" "github" {
  count = local.create_oidc ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's OIDC thumbprint — this is a well-known, stable value published by GitHub
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "${var.project_name}-github-oidc"
  }
}

data "aws_iam_policy_document" "github_actions_assume" {
  count = local.create_oidc ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to only your specific repo, only the main branch — prevents
    # any other repo or a PR branch from assuming this role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count              = local.create_oidc ? 1 : 0
  name               = "${var.project_name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume[0].json

  tags = {
    Name = "${var.project_name}-github-actions"
  }
}

# ---------- Scoped permissions: S3 upload to deployments/ prefix, SSM to run commands, describe instances to find targets ----------
data "aws_iam_policy_document" "github_actions_permissions" {
  count = local.create_oidc ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["s3:PutObject", "s3:GetObject"]
    resources = [
      "${aws_s3_bucket.backups.arn}/deployments/*"
    ]
  }

  statement {
    effect  = "Allow"
    actions = ["ssm:SendCommand"]
    resources = [
      "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript",
      "arn:aws:ec2:${var.aws_region}:*:instance/*"
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["ssm:GetCommandInvocation"]
    resources = ["*"] # this action doesn't support resource-level scoping
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"] # read-only, describe actions don't support resource scoping
  }

  statement {
    effect    = "Allow"
    actions   = ["elasticloadbalancing:DescribeLoadBalancers"]
    resources = ["*"] # read-only, describe actions don't support resource scoping
  }
}

resource "aws_iam_role_policy" "github_actions_permissions" {
  count  = local.create_oidc ? 1 : 0
  name   = "${var.project_name}-github-actions-permissions"
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.github_actions_permissions[0].json
}
