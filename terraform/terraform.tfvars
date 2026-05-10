aws_region       = "eu-west-1"
project_name     = "boutique"
instance_type    = "t3.micro"
public_key_path  = "C:/Users/Meirhan/.ssh/id_ed25519.pub"

# Restrict SSH to your own IP for security
# Find your IP at: https://checkip.amazonaws.com
# Then set: allowed_ssh_cidr = "YOUR_IP/32"
allowed_ssh_cidr = "178.91.100.200/32"

allowed_ingress_ports = [
  {
    description = "SSH"
    port        = 22
    cidr_blocks = ["0.0.0.0/0"]
  },
  {
    description = "HTTP (Nginx)"
    port        = 80
    cidr_blocks = ["0.0.0.0/0"]
  },
  {
    description = "Grafana"
    port        = 3000
    cidr_blocks = ["0.0.0.0/0"]
  },
  {
    description = "Prometheus"
    port        = 9090
    cidr_blocks = ["0.0.0.0/0"]
  }
]