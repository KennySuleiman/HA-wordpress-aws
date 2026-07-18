resource "aws_efs_file_system" "wordpress" {
  creation_token  = "${var.project_name}-wp-content"
  encrypted       = true
  throughput_mode = var.efs_throughput_mode

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS" # auto-moves infrequently accessed files to cheaper storage class
  }

  tags = {
    Name = "${var.project_name}-efs"
  }
}

# One mount target per data subnet (one per AZ) — gives EC2 instances in
# either AZ a local, low-latency path to the shared filesystem.
resource "aws_efs_mount_target" "wordpress" {
  count           = length(aws_subnet.data)
  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = aws_subnet.data[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# Access point scopes NFS access to a specific WordPress-owned directory
# with a fixed POSIX UID/GID, rather than exposing the raw EFS root.
resource "aws_efs_access_point" "wordpress" {
  file_system_id = aws_efs_file_system.wordpress.id

  posix_user {
    uid = 33 # www-data, the standard UID Docker's wordpress/nginx images run as
    gid = 33
  }

  root_directory {
    path = "/wp-content"
    creation_info {
      owner_uid   = 33
      owner_gid   = 33
      permissions = "755"
    }
  }

  tags = {
    Name = "${var.project_name}-wp-content-ap"
  }
}
