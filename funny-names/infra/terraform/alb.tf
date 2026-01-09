

resource "aws_alb" "app" {
  load_balancer_type = "application"
  subnets = values(aws_subnet.public)[*].id
  security_groups = [aws_security_group.alb.id]
  tags = merge(local.mandatory_tags ,{
    Name = "${var.project_name}-alb"
  })
}

#target group for frontend

resource "aws_lb_target_group" "frontend" {
    port = 80
    protocol = "HTTP"
    vpc_id =aws_vpc.main.id
    target_type = "ip"
    tags = merge(local.mandatory_tags,{
        Name = "${var.project_name}-frontend-target-group"
    })
}

#target group backend

resource "aws_lb_target_group" "backend" {
  port = 3000
  protocol = "HTTP"
  vpc_id = aws_vpc.main.id
  target_type = "ip"
  tags = merge(local.mandatory_tags, {
    Name = "${var.project_name}-backend-target-group"
  })
}

output "frontend_target_group_arn" {
  value = aws_lb_target_group.frontend.arn
}

output "backend_target_group_arn" {
  value = aws_lb_target_group.backend.arn
}

