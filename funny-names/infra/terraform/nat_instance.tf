## NAT instance for cheaper than NAT gateway


# # get the latest amazon linux 2 image


# data "aws_ami" "amazon_linux_2" {
#   most_recent = true
#   owners = ["amazon"]
#   filter {
#     name = "name"
#     values = ["amzn2-ami-hvm-2.0.????????-x86_64-gp2"]
#   }
# }



# # Single Nat instance 

# resource "aws_instance" "nat" {
#   ami = data.aws_ami.amazon_linux_2.id
#   instance_type = "t3.micro"
#   subnet_id = aws_subnet.public[0].id
#   security_groups = [aws_security_group.nat_instance.id]
#   source_dest_check = false

#   user_data = <<EOF
#   #!/bin/bash
#   sysctl -w net.ipv4.ip_forward=1
#   iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
#   EOF
#   tags = merge(local.mandatory_tags, {
#     Name = "${var.project_name}-nat-instance"
#   })
# }


# # single routee table for 2 private subnets

# resource "aws_route_table" "private" {
#     vpc_id = aws_vpc.main.id

#     route {
#         cidr_block = "0.0.0.0/0"
#         nat_gateway_id = aws_instance.nat.id
#     }

#     tags = merge(local.mandatory_tags, {
#         Name = "${var.project_name}-private-route-table"
#     })
# }

# # associate private route table with private subnets

# resource "aws_route_table_association" "private" {
#     subnet_id = aws_subnet.private[0].id
#     route_table_id = aws_route_table.private.id
# }

# resource "aws_route_table_association" "private" {
#     subnet_id = aws_subnet.private[1].id
#     route_table_id = aws_route_table.private.id
# }

