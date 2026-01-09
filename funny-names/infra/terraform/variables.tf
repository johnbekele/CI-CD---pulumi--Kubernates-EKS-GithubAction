variable "environment" {
    type = string
    description = "The environment to deploy the infrastructure to"
    default = "dev"
}

variable "project_name" {
    type = string
    description = "The name of the project"
    default = "funny-names"
}

variable "region" {
    type = string
    description = "The region to deploy the infrastructure to"
    default = "us-east-1"
}

variable "owner" {
    type = string
    description = "The owner of the infrastructure"
    default = "yohansdemisie@gmail.com"
}

variable "frontend_image" {
    type = string
    description = "The image of the frontend"
    
}

variable "backend_image" {
    type = string
    description = "The image of the backend"

}

variable "cost_center" {
    type = string
    description = "The cost center of the infrastructure"
}

