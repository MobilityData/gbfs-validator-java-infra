# GBFS Validator Java Infrastructure

This repository contains Terraform infrastructure configuration for the GBFS Validator service, intended for internal use at **MobilityData**.  
Access to any MobilityData-managed Google Cloud environment is **restricted** unless explicitly authorized.

---

## Setting Up a New GCP Environment

> _"All roads lead to Rome!"_  
> There are many paths to reach the same destination. Use the following steps as a **guideline** and adapt them to your local or organizational requirements.

For more information, refer to the [Google Cloud Platform documentation](https://cloud.google.com/) and the [Terraform documentation](https://www.terraform.io/).

---

## Initial Project and Remote State Setup

> _These instructions apply when creating a **new** environment._  
> For illustration purposes, the examples below assume the GCP project is `gbfs-validator-staging` and the application environment is `dev`.

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
gcloud storage buckets create gs://mobilitydata-gbfs-validator-state-staging \
  --project=gbfs-validator-staging \
  --location=northamerica-northeast1 \
  --uniform-bucket-level-access
```

### 10. Configure the Terraform Backend

Copy the file `backend.conf.rename_me` and rename it to:

```bash
backend-dev.conf
```

Populate it with valid values matching the GCP project and bucket.

### 11. Create the Deployer Service Account

```bash
gcloud iam service-accounts create gbfs-deployer-service-account \
  --display-name="GBFS Terraform Deployer"
```

### 12. Run the Environment Setup Script

```bash
../scripts/setup-environment.sh gbfs-validator-staging dev
```

### 13. Initialize Terraform

```bash
terraform init -backend-config=backend-dev.conf
```

### 14. Build and push the GBFS API docker
```bash
../scripts/docker-build-validator.sh --push -version dev-$(($(date +%s)/60))
```

### 14. Apply the Terraform Plan

```bash
terraform apply -var="environment=dev" -var=-"gbfs_api_image_version=<<TAG from previous step>>"
```

---

## You're Ready!

Happy coding!

# Adding a new Google Cloud Service

1. Locate the service list in the `.scripts/setup-environment.s` script
2. Execute the script,
```
./scripts/setup-environment.sh gbfs-validator-staging dev
```
 