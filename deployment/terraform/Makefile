.PHONY: help init plan apply destroy fmt validate lint

# Variables
CLOUD ?= aws
ENV ?= dev
TF_DIR = environments/$(CLOUD)/$(ENV)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform (CLOUD=aws ENV=dev)
	cd $(TF_DIR) && terraform init

plan: ## Run terraform plan (CLOUD=aws ENV=dev)
	cd $(TF_DIR) && terraform plan -out=tfplan

apply: ## Run terraform apply (CLOUD=aws ENV=dev)
	cd $(TF_DIR) && terraform apply tfplan

apply-auto: ## Run terraform apply with auto-approve (CLOUD=aws ENV=dev)
	cd $(TF_DIR) && terraform apply -auto-approve

destroy: ## Run terraform destroy (CLOUD=aws ENV=dev)
	cd $(TF_DIR) && terraform destroy

fmt: ## Format all Terraform files
	terraform fmt -recursive .

validate: ## Validate Terraform configuration (CLOUD=aws ENV=dev)
	cd $(TF_DIR) && terraform validate

lint: ## Run tflint (requires tflint installed)
	cd $(TF_DIR) && tflint

security: ## Run tfsec security scan
	tfsec .

cost: ## Run infracost estimate (CLOUD=aws ENV=dev)
	cd $(TF_DIR) && infracost breakdown --path .

# Global bootstrap targets
init-global: ## Initialize global resources (CLOUD=aws)
	cd global/$(CLOUD) && terraform init

apply-global: ## Apply global resources (CLOUD=aws)
	cd global/$(CLOUD) && terraform apply

# All environments for one cloud
plan-all: ## Plan all environments for a cloud (CLOUD=aws)
	@for env in dev staging production; do \
		echo "=== Planning $(CLOUD)/$$env ==="; \
		cd environments/$(CLOUD)/$$env && terraform init -input=false && terraform plan -out=tfplan && cd ../../..; \
	done

# Shortcuts
aws-dev: ## Quick: plan AWS dev
	$(MAKE) plan CLOUD=aws ENV=dev

aws-staging: ## Quick: plan AWS staging
	$(MAKE) plan CLOUD=aws ENV=staging

aws-prod: ## Quick: plan AWS production
	$(MAKE) plan CLOUD=aws ENV=production

azure-dev: ## Quick: plan Azure dev
	$(MAKE) plan CLOUD=azure ENV=dev

gcp-dev: ## Quick: plan GCP dev
	$(MAKE) plan CLOUD=gcp ENV=dev
