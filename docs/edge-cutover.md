# Cloudflare edge cutover

The public hostnames of the GBFS Validator API are served by the `mobilitydata-sites` Cloudflare Worker ([MobilityData/org-cloudflare-workers](https://github.com/MobilityData/org-cloudflare-workers), `sites/gbfs.api.mobilitydatabase.org/`). The Worker answers bots and scanners at the edge and forwards only valid `POST /validate` requests to Cloud Run, signed with the `gbfs-edge-{env}` service account. Cloud Run accepts nothing else.

This replaces the GCP load balancer and Cloud Armor. Terraform covers everything in GCP; the steps below are the parts that live outside it (Cloudflare dashboard, service account keys, one-off cleanup).

| Environment | Hostname | GCP project | Cloud Run service | Edge service account |
|---|---|---|---|---|
| `dev` | `dev.gbfs.api.mobilitydatabase.org` | `gbfs-validator-staging` | `dev-gbfs-validator-api` | `gbfs-edge-dev` |
| `qa` | `qa.gbfs.api.mobilitydatabase.org` | `gbfs-validator-staging` | `qa-gbfs-validator-api` | `gbfs-edge-qa` |
| `prod` | `gbfs.api.mobilitydatabase.org` | `gbfs-validator-prod` | `prod-gbfs-validator-api` | `gbfs-edge-prod` |

## Behavior changes

- Only `POST /validate` and its CORS preflight are served. Swagger UI (`/swagger-ui/...`) and `/v3/api-docs` are turned off on Cloud Run (`SPRINGDOC_SWAGGERUI_ENABLED=false`, `SPRINGDOC_APIDOCS_ENABLED=false`); the validator keeps them for anyone running it on their own infrastructure. The public API docs move to GitHub Pages: https://mobilitydata.github.io/gbfs-validator-java/SwaggerUI/index.html (`docs/SwaggerUI/` in gbfs-validator-java).
- Requests are rate limited and capacity is capped; see [Limits and capacity](#limits-and-capacity).
- `feedUrl` must be an `http`/`https` URL on a public host, and the body must be JSON under 16 KB.

## Limits and capacity

| Limit | Value | Where | When exceeded |
|---|---|---|---|
| Validate requests per client IP | 5 per minute, counted per Cloudflare location | Worker `ratelimits` (`wrangler.jsonc` in org-cloudflare-workers) | 429, `Retry-After: 60` |
| Request body | 16 KB | Worker `MAX_BODY_BYTES` | 413 |
| Validations per instance | 2 at once | `max_instance_request_concurrency` in `gbfs-validator/function_config.json` | Queued by Cloud Run |
| Instances | 5 in prod, 1 in dev/qa | `max_instance_count`, `max_instance_count_non_prod` in the same file | Cloud Run returns 429 after a short queue |
| Request timeout | 60 s | `timeout` in the same file | 504 |

Measured on dev (1 vCPU, 1 GiB), a validation takes about 1 to 7 s once the instance is warm, and 5 to 8 s on a cold start. Validations are CPU-bound, so two at once on one instance share its vCPU: 4 parallel validations of a large feed took 16 s in total. Prod therefore absorbs peaks with instances, not concurrency: 10 validations in flight, roughly 50 to 100 per minute depending on feed size.

Cost follows usage: an idle instance costs nothing, and each validation costs well under 0.01 CAD. The per-IP rate limit is the control on sustained use; the instance cap bounds the worst case (about 64 CAD per instance busy for a whole month). To change a limit, edit the value in the file listed above; the budget alerts below flag any unexpected spend.

## Before the cutover

1. **Cloudflare, custom rule "Challenge abusive countries"** (zone `mobilitydatabase.org`, Security rules): append `and not (http.host contains "gbfs.api.mobilitydatabase.org")` to its expression. API clients cannot solve a Managed Challenge, so without this, validator users in those countries are blocked.
2. Do not turn on Bot Fight Mode or raise the Security Level on the zone: both apply to every hostname and would challenge API clients.
3. **Validator release** with `loader.public-network-only` (gbfs-validator-java), deployed with `app_version` in step 1 of the cutover (see "Internal addresses and local files").
4. **API docs:** in [gbfs-validator-java](https://github.com/MobilityData/gbfs-validator-java/settings/pages) Settings, Pages, deploy from branch `master`, folder `/docs` (same as mobility-feed-api), once its `docs/SwaggerUI/` change is merged.

## Two-step rollout

The cutover is split so the hostnames keep working while the GCP side changes:

1. **This change** (`legacy_load_balancer_enabled = true`, the default): the load balancer, Cloud Armor and the public `allUsers` invoker stay, next to the new edge service account and its invoker. Cloud Run ingress opens to all traffic and switches to request-based billing. The hostnames keep working through the load balancer until the Worker takes them over. During this step the run.app URL is publicly invokable, as the load balancer needs it.
2. **Follow-up change**, once the Worker serves all three hostnames: set `legacy_load_balancer_enabled = false` (or delete the `load_balancer` module, its `moved` block, `infra/load-balancer/` and the `allUsers` invoker). Terraform destroys the load balancer, Cloud Armor and the public invoker, and only the edge service account can call Cloud Run.

## Cutover

The Worker serves the hostnames as **Workers Custom Domains**, not routes on proxied records. Universal SSL on the zone's Free plan only covers one subdomain level (`*.mobilitydatabase.org`), so a proxied `gbfs.api.mobilitydatabase.org` record would fail TLS, and HSTS preload makes browsers refuse it. A Custom Domain gets its own certificate and DNS record from Cloudflare, at no cost. The Worker repository deploys on every merge to `main` (Workers Builds) and declares all three Custom Domains, so the DNS switch happens for all environments at once, in step 4.

1. **Deploy Terraform** to each environment as usual: `dev` from the pull request, `qa` on merge to `main`, `prod` from the manual workflow, with `app_version` set to the validator release from "Before the cutover". The plan creates `gbfs-edge-{env}` and its invoker binding and updates the Cloud Run service. It must not destroy anything: the `moved` blocks keep the existing load balancer and public invoker.

2. **Edge service account keys**, as Worker secrets `GBFS_VALIDATOR_DEV_SA_KEY`, `GBFS_VALIDATOR_QA_SA_KEY` and `GBFS_VALIDATOR_PROD_SA_KEY`. The keys never go into Terraform state or a repository. With Wrangler logged in to the MobilityData account, from a checkout of `org-cloudflare-workers` (shown for `dev`; `qa` uses `gbfs-edge-qa@gbfs-validator-staging`, `prod` uses `gbfs-edge-prod@gbfs-validator-prod`):

   ```bash
   gcloud iam service-accounts keys create /dev/stdout --iam-account=gbfs-edge-dev@gbfs-validator-staging.iam.gserviceaccount.com | npx wrangler secret put GBFS_VALIDATOR_DEV_SA_KEY --name mobilitydata-sites
   ```

   Or create the key file, paste its content in the dashboard (Workers & Pages, `mobilitydata-sites`, Settings, Variables and Secrets, type Secret), then delete the file.

3. **Cloud Run URLs**, as Worker secrets `GBFS_VALIDATOR_DEV_URL`, `GBFS_VALIDATOR_QA_URL` and `GBFS_VALIDATOR_PROD_URL`. Each is also the `cloud_run_url` Terraform output. Workers Builds deploys keep secrets, so steps 2 and 3 are done once.

   ```bash
   gcloud run services describe dev-gbfs-validator-api --region northamerica-northeast1 --project gbfs-validator-staging --format='value(status.url)' | npx wrangler secret put GBFS_VALIDATOR_DEV_URL --name mobilitydata-sites
   ```

4. **Switch DNS by merging the Worker change.** In the `mobilitydatabase.org` DNS records, delete the grey-cloud `A` and `AAAA` records of `gbfs.api`, `qa.gbfs.api` and `dev.gbfs.api` (six records), then merge the `org-cloudflare-workers` change right away. Workers Builds deploys the Worker and creates the three Custom Domains with their DNS records and certificates; nothing else needs adding in DNS. The deploy fails if any of the six records still exists: delete it and retry the build. The hostnames are unreachable from the record deletion until the certificates are active, usually a few minutes.

5. **Check**, for each hostname:

   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' https://dev.gbfs.api.mobilitydatabase.org/
   curl -s -X POST https://dev.gbfs.api.mobilitydatabase.org/validate -H 'Content-Type: application/json' -d '{"feedUrl":"https://gbfs.lyft.com/gbfs/2.3/bay/gbfs.json"}' | head -c 300; echo
   ```

   Expected: `404` (answered by the Worker), then a validation report. The Worker repository's `verify-live` run after the merge checks the same 404s.

## After all three environments

1. **Follow-up change** with `legacy_load_balancer_enabled = false`, deployed to dev, qa and prod as usual. Then the run.app URL refuses callers without the edge identity:

   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' -X POST "$(gcloud run services describe dev-gbfs-validator-api --region northamerica-northeast1 --project gbfs-validator-staging --format='value(status.url)')/validate"
   ```

   Expected: `403`.

2. **Clean up**, per environment, the static IPs and certificate the old setup script created outside Terraform. Unattached static IPs keep billing.

   ```bash
   gcloud compute addresses delete dev-lb-ipv4 dev-lb-ipv6 --global --project gbfs-validator-staging
   gcloud compute ssl-certificates delete dev-gbfs-api-mobilitydatabase-org --global --project gbfs-validator-staging
   ```

3. Remove `roles/compute.loadBalancerAdmin` and `roles/compute.securityAdmin` from both deployer service accounts and from `scripts/setup-deployer-sa-permissions.sh`.

4. Budget alerts, set on the billing account (the deployer service account has no billing permissions on purpose). The amount must be in the billing account's currency (CAD):

   ```bash
   gcloud billing budgets create --billing-account=<BILLING_ACCOUNT_ID> --display-name="gbfs-validator-prod" --budget-amount=25CAD --filter-projects=projects/gbfs-validator-prod --threshold-rule=percent=0.5 --threshold-rule=percent=1.0
   gcloud billing budgets create --billing-account=<BILLING_ACCOUNT_ID> --display-name="gbfs-validator-staging" --budget-amount=15CAD --filter-projects=projects/gbfs-validator-staging --threshold-rule=percent=0.5 --threshold-rule=percent=1.0
   ```

## Internal addresses and local files

The Worker only sees the top-level `feedUrl`. The validator also fetches every URL listed in the discovery file, the OAuth token URL and redirect targets, and it used to read `file:` URLs, so a public discovery file could point it at internal services or local files. The validator's loader closes this with `loader.public-network-only` (on by default in the API, from the gbfs-validator-java release that includes it): every host is resolved through a resolver that rejects private, loopback and link-local addresses, the connection uses the checked address, and `file:` URLs are refused. Deploy that release (`app_version`) before or together with this cutover.

Not covered yet: the size of a downloaded file is not capped.
