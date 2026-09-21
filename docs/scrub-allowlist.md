Acceptable Files and occurences:
```text
C:\poc\eai-azure-poc\.github\workflows\ci.yml                                                                  84 POSTGRES_PASSWORD: smart_meter_password_2026 # disposable CI test value, not an actual credential
C:\poc\eai-azure-poc\.github\workflows\ci.yml                                                                  97 DATABASE_URL:
                                                                                                                  postgresql+psycopg://smart_meter_admin:smart_meter_password_2026@localhost:5432/smart_meter_warehouse #
                                                                                                                  disposable CI test value, not an actual credential
C:\poc\eai-azure-poc\.github\workflows\ci.yml                                                                  98 API_SECURITY_TOKEN: ci-only-test-token   # disposable CI test value, not an actual credential
C:\poc\eai-azure-poc\.gitleaks.toml                                                                             7 regex = '''EAI-SECRET-SECURE-KEY|smart_meter_password'''
C:\poc\eai-azure-poc\01-java-ingestion-service\src\main\java\com\utility\ingest\IntegrationClient.java         25 String cleanAuthToken = Objects.requireNonNull(authToken, "Downstream authorization token property cannot be
                                                                                                                  null");
C:\poc\eai-azure-poc\01-java-ingestion-service\src\main\resources\application.properties                        7 integration.python.auth-token=base64_encoded_smart_meter_token_string
C:\poc\eai-azure-poc\02-python-transformation-api\app\api\transform.py                                         17 API_KEY_NAME = "X-EAI-TOKEN"
C:\poc\eai-azure-poc\02-python-transformation-api\app\api\transform.py                                         18 api_key_header_guard = APIKeyHeader(name=API_KEY_NAME, auto_error=False)
C:\poc\eai-azure-poc\02-python-transformation-api\app\api\transform.py                                         34 def authenticate_request(api_key: str = Security(api_key_header_guard)):
C:\poc\eai-azure-poc\docs\DEPLOYMENT_AZURE.md                                                                 937 POSTGRES_PASSWORD: smart_meter_password_2026 # disposable CI test value, not an actual credential
C:\poc\eai-azure-poc\docs\DEPLOYMENT_AZURE.md                                                                 950 DATABASE_URL:
                                                                                                                  postgresql+psycopg://smart_meter_admin:smart_meter_password_2026@localhost:5432/smart_meter_warehouse #
                                                                                                                  disposable CI test value, not an actual credential
C:\poc\eai-azure-poc\docs\DEPLOYMENT_AZURE.md                                                                 951 API_SECURITY_TOKEN: ci-only-test-token   # disposable CI test value, not an actual credential
```

| # | File : line | Finding | Category | Decision and action |
|---|---|---|---|---|
| 1 | `.github/workflows/ci.yml` : 84, 97 | Password of the CI test database container | Disposable | Keep. Add the comment `# disposable CI test value, not a credential` to both lines and to the document mirror. Record in the allow-list. |
| 2 | `docs/DEPLOYMENT_AZURE.md` : 937, 950 | Password of the CI test database container | Disposable | Keep. Add the comment `# disposable CI test value, not a credential` to both lines and to the document mirror. Record in the allow-list. |
| 3 | `01-java-ingestion-service/src/main/resources/application.properties` : 7 | `integration.python.auth-token=base64_encoded_smart_meter_token_string` | Placeholder | Keep as a placeholder. It is overridden by the environment and grants nothing. |
| 4 | `.env` : 1, 2 (ignored file) | The local values are the **old** literals | Secret (local) | Rotate to new random values (below). The file is ignored by Git, so it is never published. |
| 5 | `IntegrationClient.java` : 25 and `transform.py` : 17 | A message string that contains the word "token", and the header name `X-EAI-TOKEN` | False positives | Record as false positives. |
