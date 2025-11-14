# Seed GitLab with a Pre-migrated Schema

GitLab's first boot spends several minutes running database migrations. You can
skip most of that delay by capturing a schema-only dump from a fully migrated
instance and baking it back into future builds.

## 1. Capture the schema dump

1. Launch a VM (production profile) and wait for GitLab to finish its initial
   boot cycle (`gitlab-db-config.service` must be `active`).
2. From the repo root, run the helper over SSH:
   ```bash
   ssh -p 2224 root@localhost 'bash -s /var/lib/gitlab/gitlab-schema.sql' \
     < scripts/gitlab/dump-schema.sh
   ```
   The script waits for PostgreSQL, confirms `schema_migrations` exists, and
   writes a schema-only `pg_dump` to the path you provide.
3. Copy the file back to your workstation:
   ```bash
   scp -P 2224 root@localhost:/var/lib/gitlab/gitlab-schema.sql artifacts/gitlab/schema.sql
   ```
4. Commit the `artifacts/gitlab/schema.sql` file (or store it in your internal
   secrets repo) so future builds can reuse it.

## 2. Tell Nix to use the seed file

Point the GitLab module at the dumped SQL file. For example, in
`infra/nixos/configs/complete-production.nix`:

```nix
services.rave.gitlab = {
  enable = true;
  publicUrl = gitlabExternalUrl;
  databaseSeedFile = ./artifacts/gitlab/schema.sql;
  # ...
};
```

When `databaseSeedFile` is set, the new `gitlab-db-seed.service` runs before
GitLab migrations and loads the dump (only if the database is still empty). Once
the seed is in place, GitLab skips the slow bootstrap and moves straight to the
runtime services.

## 3. Refresh after upgrades

Repeat the capture process whenever you bump GitLab to a new version. Using an
outdated schema dump will cause migrations to fail. A quick checklist:

- Upgrade GitLab -> boot a VM -> wait for `gitlab-db-config.service` to finish.
- Re-run `scripts/gitlab/dump-schema.sh` inside the VM.
- Replace `artifacts/gitlab/schema.sql` with the new dump and commit it.

That’s it—the next `nix build .#production` will restore this schema inside the
image, shaving several minutes from every VM launch.
