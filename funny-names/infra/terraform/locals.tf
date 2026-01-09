locals {
    mandatory_tags = {
        "project" = var.project_name
        "environment" = var.environment
        "owner" = var.owner
        "cost_center" = var.cost_center
    }
}