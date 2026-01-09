#ecs cluster 


resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
  tags = merge(local.mandatory_tags,{
    Name ="${var.project_name}-cluster"
  })
}


#front end setup ECS

#task defination front end nginx
resource "aws_ecs_task_definition" "frontend" {
  family = "frontend"
  requires_compatibilities = [ "FARGATE"]
  network_mode = "awsvpc"
  cpu = 256
  memory = 512
  tags = local.mandatory_tags


  container_definitions = jsonencode([{
    name = "frontend"
    image = var.frontend_image
    portMappings = [{containerPort = 80}]
  }]) 
}

#service defination front end nginx

resource "aws_ecs_service" "frontend" {
  name = "frontend-service"
  cluster = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count = 1
  launch_type = "FARGATE"
  tags = local.mandatory_tags

  network_configuration {
    subnets = values(aws_subnet.public)[*].id
    security_groups = [aws_security_group.ecs.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name = "frontend"
    container_port = 80
  }
}


#backedn setup ecs 

#task defination

resource "aws_ecs_task_definition" "backend" {
  family = "backend"
  requires_compatibilities = ["FARGATE"]
  network_mode = "awsvpc"
  cpu = 256
  memory = 512
  tags = local.mandatory_tags

  container_definitions = jsonencode([{
    name = "backend"
    image = var.backend_image
    portMappings = [{containerPort = 8000}]
  }])
}

# service defination

resource "aws_ecs_service" "backend" {
  name = "backend"
  cluster = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count = 1
  launch_type = "FARGATE"
  tags = local.mandatory_tags

  network_configuration {
    subnets = values(aws_subnet.private)[*].id
    security_groups = [aws_security_group.ecs.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name = "backend"
    container_port = 8000
  }
}