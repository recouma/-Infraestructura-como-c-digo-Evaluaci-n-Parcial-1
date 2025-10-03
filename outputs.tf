output "alb_dns_name" {
  description = "DNS del Application Load Balancer"
  value       = aws_lb.this.dns_name
}

output "instance_public_ips" {
  description = "IPs públicas de las EC2"
  value       = [for i in aws_instance.web : i.public_ip]
}

output "ssh_allowed_cidr" {
  description = "Rango que tiene permitido SSH"
  value       = var.allow_ssh ? (var.ssh_cidr_override != "" ? var.ssh_cidr_override : local.myip_cidr) : "SSH disabled"
}
