# Backend ECR Repository  
resource "aws_ecr_repository" "backend" {  
  name                 = "${var.project_name}-backend-${var.environment}"  
  image_tag_mutability = "MUTABLE"
  
  image_scanning_configuration {  
    scan_on_push = true  
  }
  
  tags = {  
    Name        = "${var.project_name}-backend-ecr"  
    Environment = var.environment
  }  
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["v"]
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
  
# Frontend ECR Repository  
resource "aws_ecr_repository" "frontend" {  
  name                 = "${var.project_name}-frontend-${var.environment}"  
  image_tag_mutability = "MUTABLE"
  
  image_scanning_configuration {  
    scan_on_push = true  
  }
  
  tags = {  
    Name        = "${var.project_name}-frontend-ecr"  
    Environment = var.environment  
  }  
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["v"]
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}


output "backend_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "frontend_repository" {
  value = aws_ecr_repository.frontend.repository_url
}


output "frontend_repository_arn" {
  value = aws_ecr_repository.frontend.arn
}

output "backend_repository_arn" {
  value = aws_ecr_repository.backend.arn
}