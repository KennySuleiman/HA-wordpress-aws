resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ---------- Public subnets: ALB + NAT instance ----------
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# ---------- Private subnets: EC2 WordPress instances ----------
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  }
}

# ---------- Data subnets: RDS + EFS, fully isolated ----------
resource "aws_subnet" "data" {
  count             = length(var.data_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.data_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-data-${var.availability_zones[count.index]}"
    Tier = "data"
  }
}

# ---------- Public route table ----------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------- NAT instance (t3.micro, free-tier friendly) ----------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "nat" {
  name        = "${var.project_name}-nat-sg"
  description = "Allow inbound from private subnets, outbound to internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All traffic from within the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-nat-sg"
  }
}

resource "aws_instance" "nat" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.nat_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.nat.id]
  user_data_replace_on_change = true
  source_dest_check           = false # required so it can forward traffic not addressed to itself
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -e
    dnf install -y iptables
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p

    INTERFACE=$(ip route | awk '/default/ {print $5; exit}')
    iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
    iptables -A FORWARD -i $INTERFACE -o $INTERFACE -j ACCEPT
    iptables-save > /etc/iptables-nat.rules

    cat <<'SERVICE' > /etc/systemd/system/nat-rules.service
    [Unit]
    Description=Restore NAT iptables rules
    After=network.target

    [Service]
    Type=oneshot
    ExecStart=/sbin/iptables-restore /etc/iptables-nat.rules
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable nat-rules.service
  EOF

  tags = {
    Name = "${var.project_name}-nat-instance"
  }
}

resource "aws_eip" "nat" {
  domain   = "vpc"
  instance = aws_instance.nat.id

  tags = {
    Name = "${var.project_name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# ---------- Private route table: EC2 egress via the NAT instance ----------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat.primary_network_interface_id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ---------- Data route table: no internet route at all ----------
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-data-rt"
  }
}

resource "aws_route_table_association" "data" {
  count          = length(aws_subnet.data)
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}
