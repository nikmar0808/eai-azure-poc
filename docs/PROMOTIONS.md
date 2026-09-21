| Date | From | To | Image tag (SHA) | Triggered by |
|---|---|---|---|---|
| 15-Sep-2026 | develop branch, (DEV env torn down after this SHA's build, UAT Provisioned) | uat branch (UAT env) | `fb07458c7b55aee7a34fe21a016857c4044eac7a` | promote-uat workflow_dispatch |
| 16-Sep-2026 | uat branch (DEV down, PROD Provisioned) | main branch (PROD env) | `fb07458c7b55aee7a34fe21a016857c4044eac7a` | promote-prod workflow_dispatch |

| Date | Stage | Status | Comments | Checked / Approved by |
|---|---|---|---|---|
| 16-Sep-2026 | UAT health check | PASS | {"status":"UP"} | nikmar0808 |
| 16-Sep-2026 | UAT ingest round-trip | PASS | row ingest and db record confirmed for MTR-000123 | nikmar0808 |
| 16-Sep-2026 | UAT approval | APPROVED | None | nikmar0808 |
