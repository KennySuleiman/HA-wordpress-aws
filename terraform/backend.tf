terraform {
  backend "s3" {
    bucket         = "ha-wordpress-tfstate-46349d88"
    key            = "wordpress-ha/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
