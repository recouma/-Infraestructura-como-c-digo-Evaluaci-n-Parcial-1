terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws  = { source = "hashicorp/aws",  version = ">= 5.0" }
    http = { source = "hashicorp/http", version = ">= 3.4.0" }
  }
}

provider "aws" {
  region = var.region
}

# --- Utilidades (IP pública del usuario) ---
data "http" "myip" {
  url = "https://checkip.amazonaws.com/"
}

locals {
  myip_cidr = "${chomp(data.http.myip.response_body)}/32"
  ssh_cidr  = var.ssh_cidr_override != "" ? var.ssh_cidr_override : local.myip_cidr
}

# --- AZs disponibles ---
data "aws_availability_zones" "azs" {
  state = "available"
}

# --- VPC + subredes públicas ---
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name  = "${var.project_name}-vpc"
    Owner = "dtapia"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "${var.project_name}-igw", Owner = "dtapia" }
}

resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(aws_vpc.vpc.cidr_block, 8, count.index + 1) # /24
  availability_zone       = data.aws_availability_zones.azs.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-public-${count.index + 1}", Owner = "dtapia" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project_name}-public-rt", Owner = "dtapia" }
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- AMI Amazon Linux 2 ---
data "aws_ami" "amzn2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [
      "amzn2-ami-kernel-5.10-hvm-2.0.*-x86_64-gp2",
      "amzn2-ami-kernel-5.10-hvm-2.0.*-x86_64-gp3",
      "amzn2-ami-hvm-2.0.*-x86_64-gp2",
      "amzn2-ami-hvm-2.0.*-x86_64-gp3"
    ]
  }
}

# --- Security Groups ---
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB SG (dtapia)"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg", Owner = "dtapia" }
}

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "EC2 SG (dtapia)"
  vpc_id      = aws_vpc.vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ec2-sg", Owner = "dtapia" }
}

resource "aws_security_group_rule" "ec2_http_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ec2.id
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "ec2_ssh_from_myip" {
  count             = var.allow_ssh ? 1 : 0
  type              = "ingress"
  security_group_id = aws_security_group.ec2.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [local.ssh_cidr]
}

# Diagnóstico opcional: abrir HTTP directo sólo a tu IP (no usar en producción)
resource "aws_security_group_rule" "ec2_http_from_myip_diag" {
  count             = var.diag_open_http ? 1 : 0
  type              = "ingress"
  security_group_id = aws_security_group.ec2.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [local.myip_cidr]
}

# --- ALB + TG + Listener ---
resource "aws_lb" "this" {
  name               = "dtapia-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]
  tags               = { Name = "dtapia-alb", Owner = "dtapia" }
}

resource "aws_lb_target_group" "this" {
  name     = "dtapia-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "dtapia-tg", Owner = "dtapia" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# --- EC2 (3 contenedores) ---
resource "aws_instance" "web" {
  count                       = 3
  ami                         = data.aws_ami.amzn2.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[count.index].id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data.sh", {
    IMG = element(var.docker_images, count.index)
  })

  user_data_replace_on_change = true

  tags = {
    Name      = "${var.node_name_prefix}-${count.index + 1}"
    Owner     = "dtapia"
    CheeseImg = element(var.docker_images, count.index)
    Project   = var.project_name
  }
}

resource "aws_lb_target_group_attachment" "attach" {
  count            = 3
  target_group_arn = aws_lb_target_group.this.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}
