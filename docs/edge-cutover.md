# Cloudflare edge cutover

```
client -> Cloudflare Worker (mobilitydata-sites) -> Cloud Run
```

The Worker ([org-cloudflare-workers](https://github.com/MobilityData/org-cloudflare-workers), `sites/gbfs.api.mobilitydatabase.org/`) only lets `POST /validate` through and calls Cloud Run as the `gbfs-edge-{env}` service account. It replaces the GCP load balancer and Cloud Armor.

| Env | Hostname | GCP project |
|---|---|---|
| dev | `dev.gbfs.api.mobilitydatabase.org` | `gbfs-validator-staging` |
| qa | `qa.gbfs.api.mobilitydatabase.org` | `gbfs-validator-staging` |
| prod | `gbfs.api.mobilitydatabase.org` | `gbfs-validator-prod` |

## Limits and capacity

| Limit | Value | Change it in |
|---|---|---|
| Requests per IP | 5/min per Cloudflare location, then 429 | Worker `wrangler.jsonc` |
| Request body | 16 KB, then 413 | Worker `handler.js` |
| Validations per instance | 5 at once | `gbfs-validator/function_config.json` |
| Instances | prod 20 (100 at once), dev/qa 1 (5 at once) | same file |
| Instance size | 4 vCPU, 4 GiB, JVM heap 75% | same file |
| Timeout | 90 s (Cloudflare cuts at 100 s) | same file |

Why: without the heap setting Java uses only 25% of memory and large feeds (8-12 MB) failed with `OutOfMemoryError`; 8 large validations used 1.75 GiB, so 4 GiB leaves headroom. Validation is CPU-bound (about 12 s of CPU per 12 MB feed): on 4 vCPU, 10 large feeds at once took up to 82 s against the 90 s timeout, so 5 per instance.

Other changes: Swagger UI is off on Cloud Run (docs move to [GitHub Pages](https://mobilitydata.github.io/gbfs-validator-java/SwaggerUI/index.html)); `feedUrl` must be a public http(s) URL.

## Before

- [ ] Cloudflare, Security rules, "Challenge abusive countries": append `and not (http.host contains "gbfs.api.mobilitydatabase.org")`.
- [ ] Release gbfs-validator-java with `loader.public-network-only` (blocks private addresses and local files).
- [ ] Don't enable Bot Fight Mode on the zone (it would block API clients).
- [ ] Add budget alerts (25 CAD prod, 15 CAD staging); the run.app URL is public until the follow-up:

  ```bash
  gcloud billing budgets create --billing-account=<BILLING_ACCOUNT_ID> --display-name="gbfs-validator-prod" --budget-amount=25CAD --filter-projects=projects/gbfs-validator-prod --threshold-rule=percent=0.5 --threshold-rule=percent=1.0
  ```

## Cutover

1. **Deploy this repo** to dev, qa and prod (prod with the new `app_version`). Nothing goes down: the old load balancer stays while `legacy_load_balancer_enabled = true`.

2. **Add Worker secrets** (once per env; `DEV` shown). If `wrangler` fails, delete the key it created (`gcloud iam service-accounts keys list --iam-account=...`). To rotate: new key, update the secret, delete the old key.

   ```bash
   gcloud iam service-accounts keys create /dev/stdout --iam-account=gbfs-edge-dev@gbfs-validator-staging.iam.gserviceaccount.com | npx wrangler secret put GBFS_VALIDATOR_DEV_SA_KEY --name mobilitydata-sites
   gcloud run services describe dev-gbfs-validator-api --region northamerica-northeast1 --project gbfs-validator-staging --format='value(status.url)' | npx wrangler secret put GBFS_VALIDATOR_DEV_URL --name mobilitydata-sites
   ```

3. **Switch dev and qa:** delete the A/AAAA records of `dev.gbfs.api` and `qa.gbfs.api` in Cloudflare DNS, then merge the Worker PR right away. Its Custom Domains create the new DNS records and certificates (a few minutes of downtime).

4. **Check:**

   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' https://dev.gbfs.api.mobilitydatabase.org/
   curl -s -X POST https://dev.gbfs.api.mobilitydatabase.org/validate -H 'Content-Type: application/json' -d '{"feedUrl":"https://gbfs.lyft.com/gbfs/2.3/bay/gbfs.json"}' | head -c 200
   ```

   Expect `404`, then a validation report.

   **Rollback** if the Worker deploy fails: recreate the grey-cloud (DNS only) A/AAAA records with the addresses of `{env}-lb-ipv4` / `{env}-lb-ipv6` (`gcloud compute addresses list --global --project <project>`).

5. **Switch prod** the same way, with a Worker PR that adds `gbfs.api.mobilitydatabase.org`.

## After

- [ ] Set `legacy_load_balancer_enabled = false` and deploy. The run.app URL then returns 403 to anyone but the Worker.
- [ ] Delete the old static IPs and certificates (they keep billing), then remove their creation from `scripts/setup-environment.sh` (rerunning it recreates them):

  ```bash
  for env in dev qa; do gcloud compute addresses delete $env-lb-ipv4 $env-lb-ipv6 --global --project gbfs-validator-staging; gcloud compute ssl-certificates delete $env-gbfs-api-mobilitydatabase-org --global --project gbfs-validator-staging; done
  gcloud compute addresses delete prod-lb-ipv4 prod-lb-ipv6 --global --project gbfs-validator-prod
  gcloud compute ssl-certificates delete prod-gbfs-api-mobilitydatabase-org --global --project gbfs-validator-prod
  ```

- [ ] Remove `roles/compute.loadBalancerAdmin` and `roles/compute.securityAdmin` from the deployer service accounts.
