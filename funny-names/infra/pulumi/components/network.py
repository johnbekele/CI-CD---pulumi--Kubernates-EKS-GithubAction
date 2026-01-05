import pulumi
from pulumi import ComponentResource, ResourceOptions
from pulumi_aws import ec2
from typing import List , Optional , Dict

class Network(ComponentResource):
    def __init__(self, name: str,tags: Optional[Dict[str, str]] = None, opts: ResourceOptions = None):
        super().__init__("funny-names:network", name, opts)
        tags = tags or {}
        self.vpc = self.new_resource(
            "aws:ec2/vpc:Vpc",
            name=name,
            cidr_block="10.0.0.0/16",
        )

        #internate gate way 
        self.igw = self.new_resource(
        f"{name}-internet-gateway",
        vpc_id=self.vpc.id,
        opts=ResourceOptions(parent=self),
        )

        #availability zones
        azs=pulumi.availability_zones().names[:2]

        #subnets
        self.public_subnets : List[ec2.Subnet] = []
        self.private_subnets : List[ec2.Subnet] = []

        for i , az in enumerate(azs):
            subnet_name = f"{name}-public-subnet-{i+1}"
            self.public_subnets.append(self.new_resource(
                f"{name}-public-subnet-{i+1}",
                name=subnet_name,
                vpc_id=self.vpc.id,
                availability_zone=az,
                cidr_block=f"10.0.${i+1}.0/24",
                map_public_ip_on_launch=True,
                tags=tags,
                opts=ResourceOptions(parent=self),
            ))

            self.private_subnets.append(self.new_resource(
                f"{name}-private-subnet-{i+1}",
                name=subnet_name,
                vpc_id=self.vpc.id,
                availability_zone=az,
                cidr_block=f"10.0.${i+1}.0/24",
                map_public_ip_on_launch=False,
                tags=tags,
                opts=ResourceOptions(parent=self),
            ))


            #routing table 

            self.public_route_table ={
                f"{name}-public-route-table-{i+1}":{
                    "vpc_id":self.vpc.id,
                    "routes":[
                        {
                            "cidr_block":"0.0.0.0/0",
                            "gateway_id":self.internet_gateway.id,
                        }
                    ]
                }
            }
           

            #map public subnets to public route table
            for i ,subnet in enumerate(self.public_subnets):
                ec2.RouteTableAssociation(
                    f"{name}-public-route-table-association-{i+1}",
                    subnet_id=subnet.id,
                    route_table_id=self.public_route_table[f"{name}-public-route-table-{i+1}"]["id"],
                    opts=ResourceOptions(parent=self),
                    tags=tags,
                )


             # Nat gatway for private subnets (only if you for external api use )
            self.private_route_table =[]
            self.ngws =[]

            for i ,subnet in enumerate(self.public_subnets):
                #elastic ip for nat gateway
                eip=ec2.Eip(
                    f"{name}-nat-eip-{i+1}",
                    domain="vpc",
                    opts=ResourceOptions(parent=self),
                )
                #Nat gateway
                nat_gw=ec2.NatGateway(
                    f"{name}-nat-gateway-{i+1}",
                    allocation_id=eip.id,
                    subnet_id=subnet.id,
                    tags=tags,
                    opts=ResourceOptions(parent=self ,depends_on=[self.igw]),
                )
                self.ngws.append(nat_gw)

                #private route table
                private_route_table=ec2.RouteTable(
                    f"{name}-private-route-table-{i+1}",
                    vpc_id=self.vpc.id,
                    routes=[ec2.RouteTableRouteArgs(
                        cidr_block="0.0.0.0/0",
                        nat_gateway_id=nat_gw.id,
                    )],
                    tags=tags,
                    opts=ResourceOptions(parent=self),
                )
                self.private_route_table.append(private_route_table)

                # associate private subnet with private route table
                ec2.RouteTableAssociation(
                    f"{name}-private-route-table-association-{i+1}",
                    subnet_id=subnet.id,
                    route_table_id=private_route_table.id,
                    tags=tags,
                    opts=ResourceOptions(parent=self),
                )

            self.register_outputs({
                "vpc_id": self.vpc.id,
                "public_subnets":self.public_subnets,
                "private_subnets":self.private_subnets,
                "public_route_table":self.public_route_table,
                "private_route_table":self.private_route_table,
            })