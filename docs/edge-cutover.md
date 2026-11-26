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
- Each client IP gets 5 validate requests per minute (`ratelimits` in the Worker's `wrangler.jsonc`), then a 429 with `Retry-After: 60`.
- `feedUrl` must be an `http`/`https` URL on a public host, and the body must be JSON under 16 KB.
- At most 2 validations run at once per instance, with 2 instances in prod and 1 in dev/qa (`gbfs-validator/function_config.json`). Above that, Cloud Run returns 429.

## Before the first environment

1. **Cloudflare, custom rule "Challenge abusive countries"** (zone `mobilitydatabase.org`, Security rules): append `and not (http.host contains "gbfs.api.mobilitydatabase.org")` to its expression. API clients cannot solve a Managed Challenge, so without this, validator users in those countries are blocked.
2. **Worker:** merge the `org-cloudflare-workers` change that adds `sites/gbfs.api.mobilitydatabase.org/`. Its routes do nothing until a hostname's DNS record is proxied (step 4 below), so merging early is safe. Its `verify-live` run checks the new hostnames too, and fails for each environment not yet cut over.
3. Do not turn on Bot Fight Mode or raise the Security Level on the zone: both apply to every hostname and would challenge API clients.
4. **API docs:** in [gbfs-validator-java](https://github.com/MobilityData/gbfs-validator-java/settings/pages) Settings, Pages, deploy from branch `master`, folder `/docs` (same as mobility-feed-api), once its `docs/SwaggerUI/` change is merged.

## Two-step rollout

The cutover is split so no hostname goes down:

1. **This change** (`legacy_load_balancer_enabled = true`, the default): the load balancer, Cloud Armor and the public `allUsers` invoker stay, next to the new edge service account and its invoker. Cloud Run ingress opens to all traffic and switches to request-based billing. The hostnames keep working through the load balancer until their DNS records point at the Worker. During this step the run.app URL is publicly invokable, as the load balancer needs it.
2. **Follow-up change**, once all three environments are cut over: set `legacy_load_balancer_enabled = false` (or delete the `load_balancer` module, its `moved` block, `infra/load-balancer/` and the `allUsers` invoker). Terraform destroys the load balancer, Cloud Armor and the public invoker, and only the edge service account can call Cloud Run.

## Per environment (dev, then qa, then prod)

1. **Deploy Terraform** as usual: `dev` from the pull request, `qa` on merge to `main`, `prod` from the manual workflow. The plan creates `gbfs-edge-{env}` and its invoker binding and updates the Cloud Run service. It must not destroy anything: the `moved` blocks keep the existing load balancer and public invoker.

2. **Edge service account key**, as Worker secret `GBFS_VALIDATOR_<ENV>_SA_KEY` (`DEV`, `QA` or `PROD`). The key never goes into Terraform state or the repository. With Wrangler logged in to the MobilityData account, from a checkout of `org-cloudflare-workers`:

   ```bash
   gcloud iam service-accounts keys create /dev/stdout --iam-account=gbfs-edge-dev@gbfs-validator-staging.iam.gserviceaccount.com | npx wrangler secret put GBFS_VALIDATOR_DEV_SA_KEY --name mobilitydata-sites
   ```

   Or create the key file, paste its content in the dashboard (Workers & Pages, `mobilitydata-sites`, Settings, Variables and Secrets, type Secret), then delete the file.

3. **Cloud Run URL**, as Worker secret `GBFS_VALIDATOR_<ENV>_URL`. It is also the `cloud_run_url` Terraform output. The Worker strips a trailing slash.

   ```bash
   gcloud run services describe dev-gbfs-validator-api --region northamerica-northeast1 --project gbfs-validator-staging --format='value(status.url)' | npx wrangler secret put GBFS_VALIDATOR_DEV_URL --name mobilitydata-sites
   ```

   Workers Builds deploys keep secrets, so this is done once per environment.

4. **DNS** (zone `mobilitydatabase.org`): delete the grey-cloud `A` and `AAAA` records of the hostname, then add `AAAA <hostname> 100::`, **Proxied**. `100::` is a discard address: the Worker answers every request and never contacts it. Traffic moves from the load balancer to the Worker as the change propagates; both work in the meantime.

5. **Check:**

   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' https://dev.gbfs.api.mobilitydatabase.org/
   curl -s -X POST https://dev.gbfs.api.mobilitydatabase.org/validate -H 'Content-Type: application/json' -d '{"feedUrl":"https://gbfs.lyft.com/gbfs/2.3/bay/gbfs.json"}' | head -c 300; echo
   ```

   Expected: `404` (answered by the Worker), then a validation report.

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
