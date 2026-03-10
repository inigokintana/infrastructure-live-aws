# Infrastructure Live - AWS

Stateful infrastructure definitions for AWS, organized by account and region. Uses Terragrunt to orchestrate modules from the catalog and manage Terraform state.

## Structure

```
root.hcl                    # AWS provider + S3 backend generation
prod/
  ├── account.hcl           # AWS account ID, account name
  └── us-east-1/
      ├── region.hcl        # AWS region
      └── eks-foundation-stack/
          └── terragrunt.stack.hcl  # Stack values: VPC + EKS
non-prod/
  ├── account.hcl
  └── us-east-1/
      ├── region.hcl
      └── eks-foundation-stack/
          └── terragrunt.stack.hcl
```

## Prerequisites

1. Terraform & Terragrunt installed
2. AWS credentials in `.env` file:
   ```
   export AWS_ACCESS_KEY_ID=xxx
   export AWS_SECRET_ACCESS_KEY=yyy
   export AWS_REGION=us-east-1
   ```
3. S3 bucket for Terraform state (created manually or via bootstrap)

## Usage

### Setup Local Environment

```bash
cp .env.example .env
# Edit .env with your AWS credentials
source .env
```

### Generate Stack Units

```bash
cd prod/us-east-1/eks-foundation-stack
terragrunt stack generate
```

### Plan & Apply

```bash
# Plan
terragrunt stack run plan

# Apply
terragrunt stack run apply
```

### Destroy

```bash
terragrunt stack run destroy
```

## Backend Configuration

- **Type**: AWS S3 + DynamoDB
- **Bucket**: `terragrunt-state-{account}-{region}`
- **Lock Table**: `tf-locks`
- **Encryption**: Enabled

## Hierarchy Inheritance

`root.hcl` → `account.hcl` → `region.hcl` → `terragrunt.stack.hcl`

Each level adds context (provider, backend, account ID, region) inherited by all child units.

## License

Internal use - SovereignCloudAI IaC Strategy
