

#availability zones

data "aws_availability_zones" "available" {
    state = "available"
}

#locals
locals {
  vpc_cidr = "10.0.0.0/16"
  public_subnet_bits = 8
  private_subname = 10
  az_count = 2  
  azs = slice(data.aws_availability_zones.available.names,0,2)

}

#vpc

resource "aws_vpc" "main" {
    cidr_block = local.vpc_cidr
    tags = local.mandatory_tags
}


#internate gate way 

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

#publib subnet

resource "aws_subnet" "public" {
  for_each = toset(local.azs)
  vpc_id = aws_vpc.main.id
  availability_zone = each.key
  map_public_ip_on_launch = true

  #creating cider block from azs index
  
  cidr_block = cidrsubnet(
    aws_vpc.main.cidr_block,
    8,
    index(local.azs, each.key)    
   )

   tags = merge(local.mandatory_tags, {
    Name = "public-subnet-${each.key}"
   })
}


#public route table 
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

#public route table association
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public
  subnet_id = each.value.id
  route_table_id = aws_route_table.public.id
}


# private subnet 

resource "aws_subnet" "private" {
    for_each = toset(local.azs)
    vpc_id = aws_vpc.main.id
    availability_zone = each.key

    cidr_block = cidrsubnet(
        aws_vpc.main.cidr_block,
        8,
        index(local.azs, each.key) + 10 
    )

    tags = merge(local.mandatory_tags,{
        Name = "private-subnet-${each.key}"
    })
  
}


#create elastic ip 
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = merge(local.mandatory_tags, {
    Name = "${var.project_name}-nat-eip"
  })
}

#Nat gatway 

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id = values(aws_subnet.public)[0].id
  tags = merge(local.mandatory_tags, {
    Name = "${var.project_name}-nat-gateway"
  })
}

#private route table

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id 
  }
  tags = merge(local.mandatory_tags ,
  {
    Name = "${var.project_name}-private-rt"
    })
}

# private route table association

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private
  subnet_id = each.value.id
  route_table_id = aws_route_table.private.id
}


