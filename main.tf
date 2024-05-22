provider "aws" {
  region = var.region
}

# VPC
resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"
}

# Subnets
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.example.id
  cidr_block              = cidrsubnet(aws_vpc.example.cidr_block, 8, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
}

# Internet Gateway
resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

# Security Group for ALB
resource "aws_security_group" "alb" {
  name        = "allow-http-alb"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = aws_vpc.example.id

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
}

# Security Group for EC2 instances
resource "aws_security_group" "ecs" {
  name        = "allow-http-ecs"
  description = "Allow HTTP traffic to ECS instances"
  vpc_id      = aws_vpc.example.id

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
}

# ALB
resource "aws_lb" "nginx" {
  name               = "nginx-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name = "nginx-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "nginx" {
  name     = "nginx-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.example.id
  target_type = "instance"
}

# ALB Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.nginx.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx.arn
  }
}

# Launch Template
resource "aws_launch_template" "nginx" {
  name = "nginx-template"

  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"

  user_data = base64encode(<<-EOF
              #!/bin/bash
              amazon-linux-extras install -y docker
              service docker start
              usermod -a -G docker ec2-user
              docker run -d -p 80:80 nginx:latest
              EOF
  )

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ecs.id]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "nginx" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.public[*].id
  target_group_arns    = [aws_lb_target_group.nginx.arn]

  launch_template {
    id      = aws_launch_template.nginx.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "nginx-instance"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_availability_zones" "available" {}
