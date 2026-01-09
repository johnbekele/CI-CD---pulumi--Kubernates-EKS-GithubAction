import pulumi
from pulumi import ComponentResource, ResourceOptions
import pulumi_aws as aws
from typing import List , Optional , Dict
import json
from dataclasses import dataclass


@dataclass
class IAMArgs:
    name: str
    tags: Optional[Dict[str, str]] = None
    opts: ResourceOptions = None
    s3_arn: str = None
    rds_arn: str = None
    region: str = None
    account_id: str = None

class IAM(ComponentResource):
    def __init__(
        self,
        args: IAMArgs,
    ):
        super().__init__("funny-names:iam", args.name, args.opts)
        tags = args.tags or {}

        # Trust policy for ecs /This assumes that the ecs task is being run by the ecs agent
        self.ecs_trust_policy = json.dumps({
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {
                    "Service": "ecs-tasks.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }]
        })

        # ECS task role
        self.ecs_task_role = aws.iam.Role(
            f"{args.name}-ecs-task-role",
            assume_role_policy=self.ecs_trust_policy,
            tags=tags,
            opts=ResourceOptions(parent=self),
        )

        ## --- 2. Define and Attach the Permissions Policy ---
        # Use the get_policy_document to construct the IAM policy JSON safely.
        self.task_permissions_policy_document = aws.iam.get_policy_document(
            statements=[
                aws.iam.GetPolicyDocumentStatementArgs(
                    sid="S3ReadWrite",
                    effect="Allow",
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:DeleteObject",
                        "s3:ListBucket",
                    ],
                    resources=[
                        args.s3_arn if args.s3_arn else "arn:aws:s3:::*",
                    ],
                ),
                aws.iam.GetPolicyDocumentStatementArgs(
                    sid="RdsReadWrite",
                    effect="Allow",
                    actions=[
                        "rds-data:ExecuteStatement",
                        "rds-data:BatchExecuteStatement",
                        "rds-data:BeginTransaction",
                        "rds-data:CommitTransaction",
                        "rds-data:RollbackTransaction",
                    ],
                    resources=[
                        args.rds_arn if args.rds_arn else "arn:aws:rds-data:*",
                    ],
                )
            ] 
        )


        #create Iam policy and attach to the ecs task role
        self.task_permissions_policy = aws.iam.Policy(
            f"{args.name}-task-permissions-policy",
            role=self.ecs_task_role.id,
            policy_arn=self.task_permissions_policy_document.arn,
            opts=ResourceOptions(parent=self),
        )

        #create Task excution role 
        self.task_execution_role = aws.iam.Role(
            f"{args.name}-task-execution-role",
            assume_role_policy=self.ecs_trust_policy,
            tags=tags,
            opts=ResourceOptions(parent=self),
        )

        #attach aws managed execution role policy 
        self.task_execution_role_policy_attachment = aws.iam.RolePolicyAttachment(
            f"{args.name}-task-execution-role-policy-attachment",
            role=self.task_execution_role.id,
            policy_arn=self.task_execution_role_policy_arn,
            opts=ResourceOptions(parent=self),
        )


        self.register_outputs({
            "ecs_task_role_arn": self.ecs_task_role.arn,
            "task_permissions_policy_arn": self.task_permissions_policy.arn,
        })