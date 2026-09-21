```yaml
release:
  version: "<RELEASE_VERSION>"
  git_commit: "<UAT_VALIDATED_SHA>"
  git_tag: "<GIT_TAG, if used>"

artifacts:
  java:
    repository: "eai-java-gateway"
    registry: "eaisharedacr.azurecr.io"
    tag: "<UAT_VALIDATED_SHA>"
  python:
    repository: "eai-python-validator"
    registry: "eaisharedacr.azurecr.io"
    tag: "<UAT_VALIDATED_SHA>"

infrastructure:
  terraform_workspace: "eai-prod-azure"
  resource_group: "eai-prod-rg"
  vm: "eai-prod-host"
  postgres_fqdn: "<postgres_fqdn output, Section 14.2>"
  apim_gateway_url: "<PROD_API_URL>"

deployment:
  environment: "prod"
  workflow_run: "<GITHUB_ACTIONS_RUN_URL>"
  approvers: ["<PROD_APPROVER>"]
  approved_at: ["<PROD_APPROVAL_TIMESTAMP_1>", "<PROD_APPROVAL_TIMESTAMP_2>"]
  deployed_at: "<DEPLOYMENT_TIMESTAMP>"
  verified_at: "<VERIFICATION_TIMESTAMP, Section 15.3>"
```