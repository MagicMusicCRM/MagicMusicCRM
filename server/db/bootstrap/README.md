# Database Bootstrap

Use these bootstrap notes before running application migrations on a real server.

The production database must have separate responsibilities:

- `magiccrm_owner`: owns schemas and runs migrations.
- `magiccrm_app`: used by the API at runtime and must not be superuser/schema owner.
- `magiccrm_readonly`: optional diagnostics/reporting user.

Do not commit real passwords. Generate them on the server and store them only in the deployment secret store.
