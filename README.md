# pipelines-gitlab-init

Bootstrap scripts for Gruntwork Pipelines on GitLab.

- `scripts/init.sh` — full initialization for a pipeline entrypoint job. Executed, not sourced.
- `scripts/refresh-credentials.sh` — mints a fresh Gruntwork read token and nothing else. Sourced.
- `scripts/lib/credentials.sh` — token helpers shared by both.

## Refreshing credentials

The Gruntwork read token expires one hour after it is minted, so a job that starts more than an
hour into a pipeline inherits an expired token from the `build.env` dotenv artifact. Such jobs
source `refresh-credentials.sh` before cloning:

```yaml
script:
  - git clone --depth 1 -b "$PIPELINES_GITLAB_INIT_REF" https://github.com/gruntwork-io/pipelines-gitlab-init.git /tmp/pipelines-gitlab-init
  - source /tmp/pipelines-gitlab-init/scripts/refresh-credentials.sh
  - git clone -b "$GRUNTWORK_PIPELINES_ACTIONS_REF" "https://oauth2:$PIPELINES_GRUNTWORK_READ_TOKEN@github.com/gruntwork-io/pipelines-gitlab-actions.git" /tmp/pipelines-actions
```

The job must declare an `APERTURE_OIDC_TOKEN` id token and set `API_BASE_URL`. A
`PIPELINES_GRUNTWORK_READ_TOKEN` supplied as a CI variable is used as-is and never refreshed.
