# ================================================================
# main.tf — Online Boutique infrastructure on AWS (eu-north-1)
# ================================================================

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ----------------------------------------------------------------
# VPC — isolated network for all boutique resources
# ----------------------------------------------------------------
resource "aws_vpc" "boutique" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

# ----------------------------------------------------------------
# Internet Gateway — gives the VPC a route to the internet
# ----------------------------------------------------------------
resource "aws_internet_gateway" "boutique" {
  vpc_id = aws_vpc.boutique.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

# ----------------------------------------------------------------
# Public Subnet — where the EC2 instance will live
# ----------------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.boutique.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-subnet"
    Project = var.project_name
  }
}

# ----------------------------------------------------------------
# Route Table — sends all outbound traffic through the IGW
# ----------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.boutique.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.boutique.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ----------------------------------------------------------------
# Security Group — firewall rules for the EC2 instance
# ----------------------------------------------------------------
resource "aws_security_group" "boutique" {
  name        = "${var.project_name}-sg"
  description = "Allow HTTP, Grafana, Prometheus, and SSH"
  vpc_id      = aws_vpc.boutique.id

  # SSH — port 22
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # HTTP — port 80 (Nginx → frontend)
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Grafana — port 3000
  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus — port 9090
  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic allowed
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

# ----------------------------------------------------------------
# Key Pair — upload your local public key for SSH access
# ----------------------------------------------------------------
resource "aws_key_pair" "boutique" {
  key_name   = "${var.project_name}-key"
  public_key = file(var.public_key_path)

  tags = {
    Project = var.project_name
  }
}

# ----------------------------------------------------------------
# EC2 Instance
# ----------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "boutique" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.boutique.id]
  key_name                    = aws_key_pair.boutique.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 30    # GB — enough for Docker images
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name    = "${var.project_name}-server"
    Project = var.project_name
  }
}

# ----------------------------------------------------------------
# Elastic IP — static public IP that survives instance restarts
# ----------------------------------------------------------------
resource "aws_eip" "boutique" {
  instance = aws_instance.boutique.id
  domain   = "vpc"

  tags = {
    Name    = "${var.project_name}-eip"
    Project = var.project_name
  }

  depends_on = [aws_internet_gateway.boutique]
}
