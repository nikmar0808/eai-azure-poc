# ADR-009: CI deploys to Container Apps through a single GitHub Environment (`poc`)

## Status
Accepted — October 2026

## Context
`ci.yml` was cloned from the three-environment VM design. Its deploy jobs target VMs this POC never
provisioned, and it built two of the four images. Phase B moved the runtime to Container Apps (ADR-008
records the frontend decisions). Container Apps resolve their own secrets from Key Vault, so the
pipeline no longer needs to carry any.

## Decision
1. One GitHub Environment, `poc`, with a required reviewer and a `develop`-only deployment-branch rule,
   gates both `publish-images` (push to `develop`) and `deploy-poc` (`workflow_dispatch`).
2. All four images are built, scanned and pushed by CI, tagged with the commit SHA. A tag is never rebuilt.
3. Deploying is `az containerapp update --image <registry>/<image>:<sha>`. It never builds and never
   handles a secret. Terraform ignores the image tag (`lifecycle.ignore_changes`); the pipeline owns it.
4. Scan policy: CRITICAL and HIGH findings **with a fixed version available** fail the build.
   Unfixable findings are not actionable and are ignored. Accepted fixable findings are listed in
   `.trivyignore` with a reason and an expiry date.
5. The existing `gha-deploy-dev-identity-poc` principal is reused for the one environment, with an added
   federated credential for `environment:poc`, and Contributor scoped to `poc-eai-aca-rg` only.

## Consequences
- Design Principle 4 (one principal per environment) is not exercised: there is one environment. A real
  multi-environment pipeline must restore one principal and one environment per stage.
- A single reviewer who is also the author makes the gate an audit record, not a second pair of eyes.
- `ARCHITECTURE_AZURE.md`, `DEPLOYMENT_AZURE.md` and `INFRA_VIEW_AZURE.md` still describe the VM and
  three-environment pipeline. They describe the *original* repository and are deliberately not rewritten
  here; each gains a one-line pointer to this ADR.
- `deploy-poc` smoke-tests only that revisions provision. The apps are IP-restricted (C.2), so a GitHub
  runner cannot call them; functional verification is manual from the operator's address.
