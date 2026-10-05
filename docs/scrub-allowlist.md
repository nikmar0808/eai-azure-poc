Acceptable Files and occurences:
| # | File : line | Finding | Category | Decision and action |
|---|---|---|---|---|
| 1 | `.github/workflows/ci.yml` : 118, 131 | Password of the CI test database container | Disposable | Keep. Add the comment `# disposable CI test value, not a credential` to both lines and to the document mirror. Record in the allow-list. |
| 2 | `docs/DEPLOYMENT_AZURE.md` : 937, 950 | Password of the CI test database container | Disposable | Keep. Add the comment `# disposable CI test value, not a credential` to both lines and to the document mirror. Record in the allow-list. |
| 3 | `01-java-ingestion-service/src/main/resources/application.properties` : 7 | `integration.python.auth-token=base64_encoded_smart_meter_token_string` | Placeholder | Keep as a placeholder. It is overridden by the environment and grants nothing. |
| 4 | `.env` : 1, 2 (ignored file) | The local values are the **old** literals | Secret (local) | Rotate to new random values (below). The file is ignored by Git, so it is never published. |
| 5 | `IntegrationClient.java` : 25 and `transform.py` : 17 | A message string that contains the word "token", and the header name `X-EAI-TOKEN` | False positives | Record as false positives. |
