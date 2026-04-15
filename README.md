# GBFS Validator Java Infrastructure

This repository contains Terraform infrastructure configuration for the GBFS Validator service, intended for internal use at **MobilityData**.  
Access to any MobilityData-managed Google Cloud environment is **restricted** unless explicitly authorized.

---

## GCP Project Structure

| Environment | GCP Project | Cloud Run Service | Status |
|---|---|---|---|
| `dev` | `gbfs-validator-staging` | `dev-gbfs-validator-api` | Existing |
| `qa` | `gbfs-validator-staging` | `qa-gbfs-validator-api` | To be deployed |
| `prod` | `gbfs-validator` _(to be created)_ | `prod-gbfs-validator-api` | To be created |

> **Note:** `dev` and `qa` share the same GCP project (`gbfs-validator-staging`). Each environment has its own Cloud Run service, Artifact Registry repository, runtime service account, and Terraform remote state. `prod` lives in a separate dedicated project.

---

## CI/CD Workflows

Three GitHub Actions workflows deploy the GBFS Validator API to each environment:

| Workflow | Trigger | Environment | Image version |
|---|---|---|---|
| `gbfs-validator-staging.yml` | `pull_request` | dev | `github.sha` |
| `gbfs-validator-staging.yml` | `push` to `main` | qa | `github.sha` |
| `gbfs-validator-prod.yml` | `workflow_dispatch` / `workflow_call` | prod | `github.ref_name` (release tag) |

Each env-specific workflow calls the shared reusable deployer (`gbfs-validator-deployer.yml`) which:
1. Authenticates to GCP using the deployer service account JSON key
2. Builds and pushes the Docker image to Artifact Registry
3. Runs `terraform apply` to deploy the Cloud Run service

### Required GitHub Actions Secrets

| Secret | Description |
|---|---|
| `STAGING_GCP_GBFS_VALIDATOR_SA_KEY` | Deployer SA JSON key for staging (dev + qa) |
| `PROD_GCP_GBFS_VALIDATOR_SA_KEY` | Deployer SA JSON key for prod |

### Required GitHub Actions Variables

| Variable | Value | Description |
|---|---|---|
| `GBFS_VALIDATOR_REGION` | `northamerica-northeast1` | GCP region (shared) |
| `DEV_GBFS_VALIDATOR_ENVIRONMENT` | `dev` | Environment name |
| `DEV_GBFS_VALIDATOR_PROJECT_ID` | `gbfs-validator-staging` | GCP project ID (shared with qa) |
| `DEV_GBFS_VALIDATOR_TF_STATE_BUCKET` | `dev` | Suffix for TF state bucket (`mobilitydata-gbfs-validator-state-dev`) |
| `DEV_GBFS_VALIDATOR_TF_STATE_OBJECT_PREFIX` | `terraform/state` | GCS object prefix for TF state |
| `DEV_GBFS_VALIDATOR_DEPLOYER_SA` | `gbfs-deployer-service-account@gbfs-validator-staging.iam.gserviceaccount.com` | Deployer SA email |
| `QA_GBFS_VALIDATOR_ENVIRONMENT` | `qa` | Environment name |
| `QA_GBFS_VALIDATOR_PROJECT_ID` | `gbfs-validator-staging` | GCP project ID (shared with dev) |
| `QA_GBFS_VALIDATOR_TF_STATE_BUCKET` | `qa` | Suffix for TF state bucket (`mobilitydata-gbfs-validator-state-qa`) |
| `QA_GBFS_VALIDATOR_TF_STATE_OBJECT_PREFIX` | `terraform/state` | GCS object prefix for TF state |
| `QA_GBFS_VALIDATOR_DEPLOYER_SA` | `gbfs-deployer-service-account@gbfs-validator-staging.iam.gserviceaccount.com` | Deployer SA email |
| `PROD_GBFS_VALIDATOR_ENVIRONMENT` | `prod` | Environment name |
| `PROD_GBFS_VALIDATOR_PROJECT_ID` | `gbfs-validator` _(to be created)_ | GCP project ID |
| `PROD_GBFS_VALIDATOR_TF_STATE_BUCKET` | `prod` | Suffix for TF state bucket (`mobilitydata-gbfs-validator-state-prod`) |
| `PROD_GBFS_VALIDATOR_TF_STATE_OBJECT_PREFIX` | `terraform/state` | GCS object prefix for TF state |
| `PROD_GBFS_VALIDATOR_DEPLOYER_SA` | `gbfs-deployer-service-account@gbfs-validator.iam.gserviceaccount.com` | Deployer SA email |

---

## Setting Up a New GCP Environment

> _"All roads lead to Rome!"_  
> There are many paths to reach the same destination. Use the following steps as a **guideline** and adapt them to your local or organizational requirements.

For more information, refer to the [Google Cloud Platform documentation](https://cloud.google.com/) and the [Terraform documentation](https://www.terraform.io/).

---

## Initial Project and Remote State Setup

> _These instructions apply when creating a **new** environment._  
> `dev` and `qa` already exist in `gbfs-validator-staging`. These steps apply when setting up `prod` (project `gbfs-validator`) or any future environment.  
> For illustration purposes, the examples below use `gbfs-validator-staging` as the project and `dev` as the environment — substitute accordingly.

### 1. Create a GCP Project

```bash
gcloud projects create gbfs-validator-staging --name="GBFS Validator Staging"
```

### 2. Assign a Billing Account

Link your billing account to the new project via GCP Console or CLI.

### 3. Set Up Firebase (for UI Hosting)

Create a Firebase project and link it to the GCP project.

### 4. Configure OAuth Credentials

Create OAuth client credentials via the [APIs & Services > Credentials](https://console.cloud.google.com/apis/credentials) page.  
These credentials will be passed as Terraform variables.

### 5. Create SSL Certificates

Configure Google-managed or self-managed certificates for the HTTPS Load Balancer.

### 6. Enable and Configure Identity Platform

Enable Identity Platform in the project and configure authentication providers as needed.

### 7. Authenticate with Google Cloud CLI

```bash
gcloud auth application-default login
```

### 8. Set the Active GCP Project

```bash
gcloud config set project gbfs-validator-staging
```

### 9. Create a Cloud Storage Bucket for Terraform State

```bash
gcloud storage buckets create gs://mobilitydata-gbfs-validator-state-dev \
  --project=gbfs-validator-staging \
  --location=northamerica-northeast1 \
  --uniform-bucket-level-access
```

### 10. Configure the Terraform Backend

Copy `infra/backend.conf.rename_me` to `infra/backend.conf` and populate it.  
`BUCKET_NAME` is the environment-specific **suffix** — the full bucket name becomes `mobilitydata-gbfs-validator-state-{BUCKET_NAME}` (e.g. use `dev` for the dev environment).

### 11. Run the Environment Setup Script

```bash
scripts/setup-environment.sh gbfs-validator-staging dev
```

This creates the deployer service account, grants IAM roles, enables required APIs, and sets up the Artifact Registry repository.

### 12. Generate a Deployer Service Account Key (for CI)

```bash
gcloud iam service-accounts keys create deployer-key.json \
  --iam-account=gbfs-deployer-service-account@gbfs-validator-staging.iam.gserviceaccount.com \
  --project=gbfs-validator-staging
```

Store the contents of `deployer-key.json` as the GitHub secret `DEV_GCP_GBFS_VALIDATOR_SA_KEY`. Delete the local file after.

### 13. Configure Terraform Variables

Copy `infra/vars.tfvars.rename_me` to `infra/vars.tfvars` and populate it for local runs.  
In CI, this is done automatically by `scripts/replace-variables.sh`.

### 14. Initialize Terraform

```bash
cd infra
terraform init -backend-config=backend.conf
```

### 15. Build and push the GBFS API Docker image

```bash
scripts/docker-build-validator.sh --push -version dev-$(($(date +%s)/60))
```

### 16. Apply the Terraform Plan

```bash
cd infra
terraform apply -var-file=vars.tfvars
```

---

## You're Ready!

Happy coding!

## Adding a new Google Cloud Service

1. Locate the service list in the `scripts/setup-environment.sh` script
2. Execute the script:
```
scripts/setup-environment.sh gbfs-validator-staging dev
```
 