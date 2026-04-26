# ================================================================
# terraform.tfvars — copy this file and fill in your values
# DO NOT commit this file to git if it contains sensitive values
# ================================================================

aws_region       = "eu-north-1"
project_name     = "boutique"
instance_type    = "t3.medium"
public_key_path  = "~/.ssh/id_rsa.pub"

# Restrict SSH to your own IP for security
# Find your IP at: https://checkip.amazonaws.com
# Then set: allowed_ssh_cidr = "YOUR_IP/32"
allowed_ssh_cidr = "178.91.100.200/32"
