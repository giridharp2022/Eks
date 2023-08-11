# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = var.region
  profile = var.awsprofile
}

terraform {
  backend "s3" {
    bucket = "giridhar-terraform-statefiles"
    key    = "eks/eks.tfstate"
    region = "us-east-1"
    profile= "giridhar"
  }
}

data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"    
    values = ["giridhar*"]
  }
}

data "aws_availability_zones" "available" {}

locals {
  cluster_name = "giridhar-eks"
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  tags = {
    Name = "giridhar*pri*"
  }
}

data "aws_subnet" "example" {
  for_each = toset(data.aws_subnets.private.ids)
  id       = each.value
}

data "aws_ami" "amzn-linux-2023-ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.3"

  cluster_name    = local.cluster_name
  cluster_version = "1.27"

  vpc_id                         = data.aws_vpc.selected.id
  subnet_ids                     = [for s in data.aws_subnet.example : s.id]
  cluster_endpoint_public_access = false

  eks_managed_node_group_defaults = {
    ami_id = data.aws_ami.amzn-linux-2023-ami.id

  }

  eks_managed_node_groups = {
    one = {
      name = "node-group"

      instance_types = var.instancetype

      min_size     = var.min_instance
      max_size     = var.max_instance
      desired_size = var.desired_instance
    }
  }
}


# https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/ 
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "4.7.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

resource "aws_eks_addon" "ebs-csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.20.0-eksbuild.1"
  service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
  tags = {
    "eks_addon" = "ebs-csi"
    "terraform" = "true"
  }
}