# GBFS Validator Java Infrastructure

This repository contains Terraform infrastructure configuration for the GBFS Validator service, intended for internal use at **MobilityData**.  
Access to any MobilityData-managed Google Cloud environment is **restricted** unless explicitly authorized.

---

## Deploying

Deployments are fully automated via GitHub Actions. There is nothing to build or compile manually — the CI pipeline handles everything.

| Environment | GCP Project | Trigger | URL |
|---|---|---|---|
| `dev` | `gbfs-validator-staging` | PR opened/updated, or manual (see below) | `https://dev.gbfs.api.mobilitydatabase.org/validate` |
| `qa` | `gbfs-validator-staging` | Push to `main`, or manual (see below) | `https://qa.gbfs.api.mobilitydatabase.org/validate` |
| `prod` | `gbfs-validator-prod` | Manual only (see below) | `https://gbfs.api.mobilitydatabase.org/validate` |

> **Note:** `dev` and `qa` share the same GCP project (`gbfs-validator-staging`). Each environment gets its own Cloud Run service, Artifact Registry path, runtime service account, and Terraform state. `prod` lives in a separate dedicated project.

### Request path

```
client -> Cloudflare (mobilitydatabase.org zone) -> Worker mobilitydata-sites -> Cloud Run (run.app, IAM-protected)
```

- The public hostnames are served by the `mobilitydata-sites` Cloudflare Worker ([MobilityData/org-cloudflare-workers](https://github.com/MobilityData/org-cloudflare-workers), `sites/gbfs.api.mobilitydatabase.org/`). It accepts only `POST /validate` (plus the CORS preflight), checks the request, rate limits per IP and forwards it with an ID token of the `gbfs-edge-{env}` service account. Everything else gets a 404 at the edge and never starts a Cloud Run instance.
- Once the legacy load balancer is removed (follow-up change), Cloud Run only accepts requests signed by `gbfs-edge-{env}` (`roles/run.invoker`); until then the public `allUsers` invoker stays and the run.app URL is publicly reachable. Cloud Run uses request-based billing and is capped at 5 instances of 10 concurrent validations (4 vCPU, 4 GiB) in prod and 1 in dev/qa (`gbfs-validator/function_config.json`). Request limits and capacity: [docs/edge-cutover.md](docs/edge-cutover.md#limits-and-capacity). The validator's built-in Swagger UI is turned off; the API docs are on [GitHub Pages](https://mobilitydata.github.io/gbfs-validator-java/SwaggerUI/index.html).
- The GCP load balancer and Cloud Armor are kept only during the cutover (`legacy_load_balancer_enabled`) and removed in a follow-up change. See [docs/edge-cutover.md](docs/edge-cutover.md) for the two-step rollout and the manual steps (Worker secrets, DNS, cleanup).

### Manual deployment

The staging and prod workflows can be triggered manually from the [GitHub Actions UI](https://github.com/MobilityData/gbfs-validator-java-infra/actions).

**Staging** (`gbfs-validator-staging.yml`):
- `target_environment` — choose `dev` (default) or `qa`
- `app_version` — optional. The version of `gbfs-validator-java` to deploy (e.g. `2.0.68`). Can also be a snapshot version (e.g. `2.0.69-SNAPSHOT`). Leave empty to deploy the latest release from Maven Central.

**Prod** (`gbfs-validator-prod.yml`):
- `app_version` — optional, same as above.

### How a deployment works

Both workflows call the shared reusable deployer (`gbfs-validator-deployer.yml`) which:
1. Authenticates to GCP using the deployer service account JSON key
2. Builds and pushes a Docker image to Artifact Registry
3. Runs `terraform apply` to deploy or update the Cloud Run service

### Terraform State Isolation

Each environment's state is stored under its own prefix in a shared bucket:
- Staging: `mobilitydata-gbfs-validator-state-staging/{env}/terraform/state`
- Prod: `mobilitydata-gbfs-validator-state-prod/prod/terraform/state`

This means `terraform apply` for one environment cannot affect another.

### Required GitHub Actions Secrets

| Secret | Description |
|---|---|
| `STAGING_GCP_GBFS_VALIDATOR_SA_KEY` | Deployer SA JSON key for staging (all staging envs) |
| `PROD_GCP_GBFS_VALIDATOR_SA_KEY` | Deployer SA JSON key for prod |

### Required GitHub Actions Variables

| Variable | Value | Description |
|---|---|---|
| `GBFS_VALIDATOR_REGION` | `northamerica-northeast1` | GCP region (shared) |
| `STAGING_GBFS_VALIDATOR_PROJECT_ID` | `gbfs-validator-staging` | Staging GCP project ID |
| `STAGING_GBFS_VALIDATOR_TF_STATE_BUCKET` | `mobilitydata-gbfs-validator-state-staging` | Staging TF state bucket (shared) |
| `STAGING_GBFS_VALIDATOR_DEPLOYER_SA` | `gbfs-deployer-service-account@gbfs-validator-staging.iam.gserviceaccount.com` | Staging deployer SA |
| `PROD_GBFS_VALIDATOR_PROJECT_ID` | `gbfs-validator-prod` | Prod GCP project ID |
| `PROD_GBFS_VALIDATOR_TF_STATE_BUCKET` | `mobilitydata-gbfs-validator-state-prod` | Prod TF state bucket |
| `PROD_GBFS_VALIDATOR_DEPLOYER_SA` | `gbfs-deployer-service-account@gbfs-validator-prod.iam.gserviceaccount.com` | Prod deployer SA |

---

## Setting Up a New GCP Environment

> _"All roads lead to Rome!"_  
> There are many paths to reach the same destination. Use the following steps as a **guideline** and adapt them to your local or organizational requirements.

For more information, refer to the [Google Cloud Platform documentation](https://cloud.google.com/) and the [Terraform documentation](https://www.terraform.io/).

---

## Initial Project and Remote State Setup

> _These instructions apply when creating a **new** environment._  
> `dev` and `qa` already exist in `gbfs-validator-staging`. These steps apply when setting up `prod` (project `gbfs-validator-prod`) or any future environment.  
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

### 5. TLS

Nothing to do: Cloudflare terminates TLS for the public hostname, and Cloud Run serves its run.app URL over TLS.

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

Copy `infra/backend.conf.rename_me` to `infra/backend.conf` and populate it.  
`BUCKET_NAME` is the full GCS bucket name (e.g. `mobilitydata-gbfs-validator-state-staging`).  
`ENVIRONMENT` is the environment name (e.g. `dev`, `qa`) — it becomes the state prefix to isolate each environment's state within the shared bucket.

### 11. Run the Environment Setup Script

```bash
# Staging (dev or qa):
scripts/setup-environment.sh gbfs-validator-staging dev

# Prod (uses a separate AR repo):
scripts/setup-environment.sh gbfs-validator-prod prod northamerica-northeast1 gbfs-validator
```

This script:
- Creates the deployer service account and grants IAM roles
- Enables required Google APIs
- Creates (or verifies) the shared Artifact Registry repository
- Creates the legacy load balancer's static IPs (`{env}-lb-ipv4`, `{env}-lb-ipv6`) and SSL certificate, needed only while `legacy_load_balancer_enabled` is true

### 11a. Connect the Cloudflare edge

After the first Terraform deploy of the environment, follow [docs/edge-cutover.md](docs/edge-cutover.md): create the edge service account key, add the Worker secrets, and hand `{env}.gbfs.api.mobilitydatabase.org` to the Worker as a Workers Custom Domain (delete its old DNS records; the Custom Domain creates its own record and certificate).

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
 