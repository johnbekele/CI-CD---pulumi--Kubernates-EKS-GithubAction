

#ALB security group 
resource "aws_security_group" "alb" {
  vpc_id = aws_vpc.main.id



  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic from the internet"
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic from the internet"
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all traffic"
  }
  tags = merge(local.mandatory_tags, {
    Name = "alb-security-group"
  })
}

#ECS security group

#frontend specific security group
resource "aws_security_group" "frontend" {
    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 3000
        to_port = 3000
        protocol = "tcp"
        security_groups = [aws_security_group.alb.id]
        description = "Allow traffic from ALB"
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Allow all traffic"
    }
    tags = merge(local.mandatory_tags, {
        Name = "ecs-frontend-security-group"
    })
}

#backend specific security group

resource "aws_security_group" "ecs" {
    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 8000
        to_port = 8000
        protocol = "tcp"
        security_groups = [aws_security_group.frontend.id]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        security_groups = [ aws_security_group.frontend.id ]
    }

    tags = merge(local.mandatory_tags, {
        Name = "ecs-backend-security-group"
    })
  
}


# nat_instance security group

resource "aws_security_group" "nat_instance" {
    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = [aws_vpc.main.cidr_block]
        description = "Allow all traffic"
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Allow all traffic"
    }
   
    tags = merge(local.mandatory_tags, {
        Name = "nat-instance-security-group"
    })

}






