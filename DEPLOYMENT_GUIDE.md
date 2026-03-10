# AWS Infrastructure Live - Deployment Guide

This guide covers deploying the AWS EKS foundation stack (VPC + EKS cluster).

## Prerequisites

- [x] AWS account with admin access
- [x] AWS CLI configured locally
- [x] Terraform 1.14.0+
- [x] Opentofu 1.11.0+
- [x] Terragrunt 0.90.0+
- [x] kubectl for Kubernetes verification

## Initial Setup

### 1. Configure AWS Credentials

```bash
# Option A: AWS CLI configure
aws configure
# Enter your Access Key ID and Secret
# Default region: us-east-1

# Option B: Environment variables
export AWS_ACCESS_KEY_ID=your-key-id
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_REGION=us-east-1

# Verify
aws sts get-caller-identity
```

### 2. Create S3 Backend Bucket

```bash
# Edit infrastructure-live-aws/root.hcl and check bucket naming:
# "terragrunt-state-${account_name}-${region}"

# Create bucket for prod
aws s3api create-bucket \
  --bucket terragrunt-state-prod-us-east-1-058264397013 \
  --region us-east-1

# Create bucket for non-prod
aws s3api create-bucket \
  --bucket terragrunt-state-non-prod-us-east-1-576282838775 \
  --region us-east-1

# Enable versioning on both
aws s3api put-bucket-versioning \
  --bucket terragrunt-state-prod-us-east-1-058264397013 \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-versioning \
  --bucket terragrunt-state-non-prod-us-east-1 \
  --versioning-configuration Status=Enabled
```

### 3. Create DynamoDB Lock Table

```bash
# Create lock table for state locking
aws dynamodb create-table \
  --table-name tf-locks-aws-058264397013 \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1
```

### 4. Update AWS Account IDs

Edit the account configuration files:

```bash
# prodaccount.hcl
cat > prod/account.hcl <<EOF
locals {
  account_name = "prod"
  account_id   = "YOUR_PROD_ACCOUNT_ID"  # Get from: aws sts get-caller-identity
}
EOF

# non-prod account.hcl
cat > non-prod/account.hcl <<EOF
locals {
  account_name = "non-prod"
  account_id   = "YOUR_NON_PROD_ACCOUNT_ID"
}
EOF
```

## Deployment Workflow

### Phase 1: Non-Production Deployment (Recommended First)

#### 1a. Navigate to Non-Prod Stack

```bash
cd infrastructure-live-aws/non-prod/us-east-1/eks-foundation-stack
```

#### 1b. Generate Stack

```bash
terragrunt stack generate

# Verify generation
ls -la .terragrunt-stack/
# Should show: vpc/ eks/ directories
```

#### 1c. Initialize Terraform

```bash
terragrunt stack run init
```

This will:
- Download Terraform providers
- Initialize S3 backend
- Create S3 bucket if not exists
- Create .terraform.lock.hcl

#### 1d. Plan Deployment

```bash
#terragrunt stack run plan -out=tfplan
terragrunt stack run plan
terragrunt stack run apply

# Output should show:
# Plan: XX to add, 0 to change, 0 to destroy
```

Review the resources:
- `aws_vpc` - Virtual Private Cloud (10.100.0.0/16 for non-prod)
- `aws_subnet` - Public and private subnets
- `aws_nat_gateway` - NAT for private subnet outbound traffic
- `aws_internet_gateway` - IGW for public subnet
- `aws_eks_cluster` - EKS cluster
- `aws_eks_node_group` - EKS worker nodes (1-2 for non-prod)

#### 1e. Apply Deployment

```bash
terragrunt stack run apply tfplan

# Or auto-approve (not recommended for prod)
terragrunt stack run apply -auto-approve
```

**Expected Duration**: 25-40 minutes

Watch the logs:
```
aws_vpc.main: Creating...
aws_internet_gateway.main: Creating...
aws_subnet.public[0]: Creating...
... (many resources)
aws_eks_node_group.main: Still creating... [15m30s elapsed]
aws_eks_cluster.main: Creation complete after 12m45s
aws_eks_node_group.main: Creation complete after 18m10s

Apply complete! Resources added: 23
```

#### 1f. Verify Non-Prod Deployment

```bash
# Get cluster info
aws eks describe-cluster --name non-prod-eks-primary --region us-east-1

# Update kubeconfig
aws eks update-kubeconfig \
  --name non-prod-eks-primary \
  --region us-east-1 \
  --kubeconfig ~/.kube/config-non-prod

# Set KUBECONFIG
export KUBECONFIG=~/.kube/config-non-prod

# Verify cluster access
kubectl cluster-info
kubectl get nodes
kubectl get pods -A

# Expected output:
# NAME                         STATUS   ROLES    AGE     VERSION
# ip-10-100-x-x.ec2.internal   Ready    <none>   2m10s   v1.28.x
```

### Phase 2: Production Deployment

#### 2a. Understand Production Differences

```hcl
# Non-prod vs Prod in terragrunt.stack.hcl:

# NON-PROD:
# vpc_cidr = "10.100.0.0/16"                  # Different CIDR
# cluster_name = "non-prod-eks-primary"       # 
# node_group_desired_size = 1                 # Smaller
# node_instance_type = "t3.small"             # Cheaper

# PROD:
# vpc_cidr = "10.0.0.0/16"                    # 
# cluster_name = "prod-eks-primary"
# node_group_desired_size = 2                 # HA setup
# node_instance_type = "t3.medium"            # Better resources
```

#### 2b. Deploy Production (Similar steps)

```bash
cd infrastructure-live-aws/prod/us-east-1/eks-foundation-stack

terragrunt stack generate
terragrunt stack run init
terragrunt stack run plan -out=tfplan

# Review plan carefully
# Then apply:
terragrunt stack run apply tfplan
```

#### 2c. Monitor Production Deployment

```bash
# Watch EKS cluster creation in real-time
aws eks describe-cluster --name prod-eks-primary \
  --query 'cluster.[name,status,platformVersion]'

# In another terminal, watch node group
aws ec2 describe-instances \
  --filters "Name=tag:aws:eks:cluster-name,Values=prod-eks-primary" \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,PrivateIpAddress]'
```

## Verification Checklist

- [ ] S3 bucket contains state files (`prod-us-east-1/eks/terraform.tfstate`)
- [ ] DynamoDB shows lock table with entries during apply
- [ ] VPC created with correct CIDR (prod: 10.0.0.0/16, non-prod: 10.100.0.0/16)
- [ ] 2 Public subnets and 2 Private subnets exist
- [ ] NAT Gateway provisioned and associated with private subnets
- [ ] EKS cluster status is `ACTIVE`
- [ ] 2 worker nodes (t3.medium) in non-prod, 2 worker nodes in prod
- [ ] kubectl can connect to cluster
- [ ] coredns and kube-proxy pods running in kube-system namespace

```bash
# Full verification script
CLUSTER_NAME=prod-eks-primary
REGION=us-east-1

echo "=== Cluster Status ==="
aws eks describe-cluster --name $CLUSTER_NAME --region $REGION \
  --query 'cluster.[name,status,endpoint,platformVersion]'

echo "=== Node Groups ==="
aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION

echo "=== Nodes ==="
kubectl get nodes -o wide

echo "=== Core Pods ==="
kubectl get pods -n kube-system

echo "=== Backend State ==="
aws s3 ls s3://terragrunt-state-prod-$REGION/prod/$REGION/eks-foundation-stack/
```

## Updating the Stack

### Modify VPC CIDR

```bash
# Edit prod/us-east-1/eks-foundation-stack/terragrunt.stack.hcl
# Change vpc_cidr = "10.0.0.0/16" to "10.1.0.0/16"

terragrunt stack run plan
# Plan should show subnet changes

terragrunt stack run apply
```

### Update Node Count

```bash
# Edit terragrunt.stack.hcl
# Change: node_group_desired_size = 3

terragrunt stack run apply -auto-approve
# Takes ~5 minutes to add new nodes
```

### Upgrade Kubernetes Version

```bash
# Edit terragrunt.stack.hcl
# Change: kubernetes_version = "1.29"

terragrunt stack run plan
# Shows: cluster version upgrade

terragrunt stack run apply
# Cluster upgrade (5-10 minutes)
# Node group will upgrade automatically
```

## Troubleshooting

### Error: "Unable to assume role"

**Cause**: IAM permissions insufficient

**Solution**:
```bash
# Verify IAM user/role has these permissions:
# - ec2:*
# - eks:*
# - iam:*
# - s3:*
# - dynamodb:*

aws iam get-user
aws iam list-attached-user-policies --user-name YOUR_USERNAME
```

### Error: "S3 bucket does not exist"

**Solution**:
```bash
# Verify bucket exists
aws s3 ls | grep terragrunt-state

# Or create it
aws s3api create-bucket --bucket terragrunt-state-prod-us-east-1 --region us-east-1
```

### EKS Nodes not coming online

**Cause**: Security group or networking issue

**Solution**:
```bash
# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:aws:eks:cluster-name,Values=prod-eks-primary"

# Check network ACLs
aws ec2 describe-network-acls \
  --filters "Name=association.vpc-id,Values=VPC_ID"

# Verify IAM role for nodes has correct permissions
aws iam get-role --role-name prod-eks-primary-worker-role
```

### kubectl: Unable to connect to cluster

**Solution**:
```bash
# Update kubeconfig
aws eks update-kubeconfig --name prod-eks-primary --region us-east-1

# Verify config
cat ~/.kube/config

# Check cluster endpoint
aws eks describe-cluster --name prod-eks-primary --query 'cluster.endpoint'

# Test connectivity
curl -k $(aws eks describe-cluster --name prod-eks-primary --query 'cluster.endpoint' --output text)/api/v1/nodes
```

## Cleanup

### Destroy Non-Production (Safe for Testing)

```bash
cd infrastructure-live-aws/non-prod/us-east-1/eks-foundation-stack
terragrunt stack run destroy

# Confirm destruction
terraform destroy -auto-approve
```

### Destroy Production (Dangerous!)

```bash
# ⚠️ This deletes all production infrastructure
cd infrastructure-live-aws/prod/us-east-1/eks-foundation-stack
terragrunt stack run destroy

# Manual confirmation required twice
# Verify destruction:
aws eks list-clusters  # Should be empty
aws ec2 describe-vpcs --filters "Name=cidr,Values=10.0.0.0/16"  # Should be empty
```

## Next Steps

- Deploy workloads to the EKS cluster
- Install ingress controller (nginx, ALB)
- Setup monitoring (CloudWatch, Prometheus)
- Configure autoscaling (karpenter, cluster-autoscaler)
- Integrate with CI/CD pipeline
