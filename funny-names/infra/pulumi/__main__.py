"""An AWS Python Pulumi program"""

import pulumi
from pulumi_aws import s3
from components.network import Network
from components.security import Security
from config import app_name, env


#=============================================================================
# Configuration
#=============================================================================

resource_owner=pulumi.Config("funny-app-dev").require("resourceOwner")
app_name=pulumi.Config("funny-app-dev").require("appName")
env=pulumi.Config("funny-app-dev").require("env")
resource_owner=pulumi.Config("funny-app-dev").require("resourceOwner")

tags={
    "pulumi:template": "aws-python",
    "resourceOwner": resource_owner,
    "appName": app_name,
    "env": env,
}

#=============================================================================
# network component
#=============================================================================
vpc=Network(app_name,env,tags)
public_subnets=vpc.public_subnets
private_subnets=vpc.private_subnets

#security group component
alb_sg=Security(app_name,80,80,vpc.vpc,tags)
ecs_sg=Security(app_name,80,80,vpc.vpc,tags)
backend_sg=Security(app_name,443,443,vpc.vpc,tags)

