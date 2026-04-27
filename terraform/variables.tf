variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Prefix applied to all resource names"
  type        = string
  default     = "boutique"
}

variable "instance_type" {
  description = "EC2 instance type. t3.medium recommended for running all services"
  type        = string
  default     = "t2.micro"   # 2 vCPU, 4GB RAM
}

variable "public_key_path" {
  description = "Path to your local SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into the instance. Restrict to your IP for security"
  type        = string
  default     = "0.0.0.0/0"   # change to your IP: e.g. "203.0.113.5/32"
}
