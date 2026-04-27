output "public_ip" {
  description = "Static public IP address of the boutique server"
  value       = aws_eip.boutique.public_ip
}

output "public_dns" {
  description = "Public DNS hostname of the instance"
  value       = aws_eip.boutique.public_dns
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.boutique.id
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh ubuntu@${aws_eip.boutique.public_ip}"
}

output "app_urls" {
  description = "Service URLs once your stack is running"
  value = {
    app        = "http://${aws_eip.boutique.public_ip}"
    grafana    = "http://${aws_eip.boutique.public_ip}:3000"
    prometheus = "http://${aws_eip.boutique.public_ip}:9090"
  }
}
