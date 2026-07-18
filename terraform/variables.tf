variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used as a prefix for resource naming"
  type        = string
  default     = "ha-wordpress"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (ALB + NAT instance), one per AZ"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private subnets (EC2 WordPress instances), one per AZ"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "data_subnet_cidrs" {
  description = "CIDRs for isolated data subnets (RDS + EFS), one per AZ"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "nat_instance_type" {
  description = "Instance type for the NAT instance (t3.micro is free-tier eligible)"
  type        = string
  default     = "t3.micro"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "wordpress"
}

variable "db_username" {
  description = "Master username for RDS"
  type        = string
  default     = "wpadmin"
}

variable "db_instance_class" {
  description = "RDS instance class (db.t3.micro is free-tier eligible for the first RDS instance)"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0"
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode: bursting (cost-effective, scales with storage) or provisioned"
  type        = string
  default     = "bursting"
}

variable "ec2_instance_type" {
  description = "Instance type for WordPress EC2 instances (t3.micro is free-tier eligible)"
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  description = "Minimum instances in the Auto Scaling Group"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum instances in the Auto Scaling Group"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Desired instances in the Auto Scaling Group"
  type        = number
  default     = 2
}
