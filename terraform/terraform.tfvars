aws_region       = "eu-west-1"
project_name     = "boutique"
instance_type    = "c7i-flex.large"
public_key_path  = "C:/Users/Meirhan/.ssh/id_ed25519.pub"
eks_node_instance_type = "t3.medium"

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
  },
  { 
    description = "App k8s",    
    port = 30080, 
    cidr_blocks = ["0.0.0.0/0"] 
  },
  { 
    description = "Grafana k8s",
    port = 30030, 
    cidr_blocks = ["0.0.0.0/0"] 
  }
]