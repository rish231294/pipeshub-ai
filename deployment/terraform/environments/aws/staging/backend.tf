# -----------------------------------------------------------------------------
# Terraform Backend Configuration - AWS Staging
# State is stored in S3 with DynamoDB locking (created by global/aws bootstrap)
# -----------------------------------------------------------------------------

terraform {
  backend "s3" {
    bucket         = "pipeshub-ai-terraform-state-ACCOUNT_ID"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "pipeshub-ai-terraform-locks"
  }
}
