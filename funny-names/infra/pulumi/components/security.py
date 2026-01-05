from pulumi import ComponentResource, ResourceOptions
from pulumi_aws import ec2, securityhub
from typing import List , Optional , Dict

class Security(ComponentResource):
    def __init__(
        self,
        name: str,
        BackendPort: int,
        FrontendPort: int,
        vpc: ec2.Vpc,
        tags: Optional[Dict[str, str]] = None,
        opts: ResourceOptions = None
    ):
        super().__init__("funny-names:security", name, opts)
        tags = tags or {}

        # Alb security group

        self.alb_sg = ec2.SecurityGroup(
            f"{name}-alb-security-group",
            vpc_id=vpc.id,
            description="Security group for ALB",
            ingress=[
                ec2.SecurityGroupIngressArgs(
                    from_port=80,
                    to_port=80,
                    protocol="tcp",
                    cidr_blocks=["0.0.0.0/0"],
                )
            ],
            egress=[
                ec2.SecurityGroupEgressArgs(
                    from_port=0,
                    to_port=0,
                    protocol="-1",
                    cidr_blocks=["0.0.0.0/0"],
                )
            ],
            tags=tags,
            opts=ResourceOptions(parent=self),
        )


        # ECS security group

        self.ecs_sg = ec2.SecurityGroup(
            f"{name}ecs-security-group",
            vpc_id=vpc.id,
            description="Security group for ECS",
            ingress=[
                ec2.SecurityGroupIngressArgs(
                    protocol="tcp",
                    from_port=FrontendPort,
                    to_port=FrontendPort,
                    security_groups=[self.alb_sg.id],
                    description="Allow traffic from ALB",
                ),
                ec2.SecurityGroupIngressArgs(
                    protocol="tcp",
                    from_port=BackendPort,
                    security_groups=[self.alb_sg.id],
                    description="Allow traffic from ALB",
                )
            ],
            egress=[
                ec2.SecurityGroupEgressArgs(
                    protocol="-1",
                    from_port=0,
                    to_port=0,
                    cidr_blocks=["0.0.0.0/0"],
                )
            ],
            tags=tags,
            opts=ResourceOptions(parent=self),
        )

        # backedn specific security group
        self.backend_sg = ec2.SecurityGroup(
            f"{name}-backend-security-group",
            vpc_id=vpc.id,
            description="Security group for backend",

            ingress=[
                ec2.SecurityGroupIngressArgs(
                    protocol="tcp",
                    from_port=443,
                    to_port=443,
                    security_groups=[self.ecs_sg.id],
                    description="HTTPs from ECS",
                )
            ],
            egress=[
                ec2.SecurityGroupEgressArgs(
                    protocol="-1",
                    from_port=0,
                    to_port=0,
                    cidr_blocks=["0.0.0.0/0"],
                )
            ],
            tags=tags,
            opts=ResourceOptions(parent=self),
        )

        # Register outputs
        self.register_outputs({
            "alb_sg": self.alb_sg.id,
            "ecs_sg": self.ecs_sg.id,
            "backend_sg": self.backend_sg.id,
        })