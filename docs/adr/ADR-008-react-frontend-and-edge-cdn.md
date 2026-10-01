# ADR-008: React read-path frontend, served by Nginx, fronted by Azure Front Door Standard

## Status
Accepted — 2026-09-30

## Context
POC 1's Azure window had spare runway (days and credit) after Phase B4 closed
finding F27. Three things were wanted: a second frontend surface built in
React + TypeScript (distinct from B2's Node/Express write-path BFF), a
read-only query screen against the data B4/B2 already wrote, and a look at
how Azure's current edge/CDN offering works. Three design questions needed
answers, each with a real trade-off:

1. How does the React app reach python-validator, which is internal-only
   by Phase C's own C.2 decision?
2. Which Azure edge/CDN product, and which tier?
3. Custom domain, or the platform's own endpoint hostname?

## Decision
1. **Nginx serves the built React static assets and reverse-proxies
   `/api/*` to `python-validator`'s internal DNS name.** This keeps
   `python-validator` internal-only — C.2's decision is not reopened — and
   avoids a second Node/Express server that would only repeat B2's own
   pattern rather than demonstrate a different one. Nginx's official Docker
   image supports environment-variable substitution into its config at
   container start (`/etc/nginx/templates/*.template` -> `envsubst`),
   which is used to inject the shared API token into the proxy, the same
   way `node-frontend`'s own server code already attaches it — here done at
   the reverse-proxy layer instead of application code.
2. **Azure Front Door *Standard*, with a public origin.** Azure CDN
   (classic, all publishers) is on a Microsoft-directed retirement path as
   of 2026; Front Door Standard/Premium is the current, actively-sold
   product family. Premium adds Private Link (an origin that never touches
   the public internet) but requires a Workload Profiles Container Apps
   environment, not the Consumption-only one this POC runs — a real
   architecture change, not justified for the days remaining in this
   window. Standard, at a public origin, is layered on top of what already
   exists with no change to `infra/aca`'s environment type.
3. **No custom domain.** Front Door's own default endpoint hostname
   (`<name>.z01.azurefd.net`-shaped) demonstrates the routing and caching
   mechanics fully; a custom domain adds DNS delegation and certificate
   issuance latency that teaches nothing new here.

## Consequences
- `java-gateway` remains unused by any frontend, on both the write and
  read paths — a standing fact, not something this ADR tries to fix.
- Cache-bypass for `/api/*` is done with two separate Front Door routes
  sharing one origin group (one cached, one not) rather than a Rules
  Engine rule — the simpler, provider-portable mechanism, at the cost of
  not demonstrating Front Door's own rule-authoring UI/API.
- Reaching Private Link + Workload Profiles later (POC 7, or a
  production-shaped follow-up) is a real, larger piece of work, not a
  small toggle on what this ADR builds.
