# pipelines-gitlab-init

Bootstrap scripts for Gruntwork Pipelines on GitLab.

- `scripts/init.sh` — full initialization for a pipeline entrypoint job.
- `scripts/refresh-credentials.sh` — mints a fresh Gruntwork read token and nothing else.
- `scripts/lib/credentials.sh` — token helpers shared by both.

## Refreshing credentials

The Gruntwork read token expires one hour after it is minted, so a job that starts more than an
hour into a pipeline inherits an expired token from the `build.env` dotenv artifact. Such jobs run
`refresh-credentials.sh` before cloning. Both scripts write the token to `build.env`, which the
runner only applies to later jobs, so re-read it to pick the refreshed token up in the job shell:

```yaml
script:
  - rm -rf /tmp/pipelines-gitlab-init && gw-git-clone --depth 1 -b "$PIPELINES_GITLAB_INIT_REF" https://github.com/gruntwork-io/pipelines-gitlab-init.git /tmp/pipelines-gitlab-init
  - /tmp/pipelines-gitlab-init/scripts/refresh-credentials.sh
  - set -a && source build.env && set +a
  - rm -rf /tmp/pipelines-actions && gw-git-clone --depth 1 -b "$GRUNTWORK_PIPELINES_ACTIONS_REF" "https://oauth2:$PIPELINES_GRUNTWORK_READ_TOKEN@github.com/gruntwork-io/pipelines-gitlab-actions.git" /tmp/pipelines-actions
```

The job must declare an `APERTURE_OIDC_TOKEN` id token and set `API_BASE_URL`; the refresh fails
if either is missing. A `PIPELINES_GRUNTWORK_READ_TOKEN` supplied as a CI variable is used as-is
and never refreshed.
