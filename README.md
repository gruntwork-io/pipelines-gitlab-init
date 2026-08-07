# pipelines-gitlab-init

Bootstrap scripts for Gruntwork Pipelines on GitLab. This repository is public and is cloned
without credentials, which is what makes it the right place to obtain the Gruntwork read
token needed to clone everything else.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/init.sh` | Full initialization for a pipeline entrypoint job: obtains the Gruntwork read token, clones `pipelines-gitlab-actions`, installs the Pipelines CLI, and collapses merge request notes from previous commits. Executed, not sourced. |
| `scripts/refresh-credentials.sh` | Obtains a fresh Gruntwork read token for the current job and nothing else. Intended to be sourced at the start of any job that clones a Gruntwork repository. |
| `scripts/lib/credentials.sh` | Sourceable library shared by both of the above: mint, verify and publish the Gruntwork read token. |
| `scripts/pipelines-credentials.mjs` | Exchanges the job's `APERTURE_OIDC_TOKEN` with the Gruntwork API for a read token. |

## Refreshing credentials

The Gruntwork read token is a GitHub App installation token with a one hour lifetime. In
GitLab it is minted once in the `orchestrate` job and passed to downstream jobs through the
`build.env` dotenv artifact, so a job that starts more than an hour into a pipeline inherits
an expired token. Jobs avoid this by sourcing `refresh-credentials.sh` before cloning:

```yaml
script:
  - git clone --depth 1 -b "$PIPELINES_GITLAB_INIT_REF" https://github.com/gruntwork-io/pipelines-gitlab-init.git /tmp/pipelines-gitlab-init
  - source /tmp/pipelines-gitlab-init/scripts/refresh-credentials.sh
  - git clone -b "$GRUNTWORK_PIPELINES_ACTIONS_REF" "https://oauth2:$PIPELINES_GRUNTWORK_READ_TOKEN@github.com/gruntwork-io/pipelines-gitlab-actions.git" /tmp/pipelines-actions
```

The job must declare an `APERTURE_OIDC_TOKEN` id token with the `aud` of the Gruntwork API,
and `API_BASE_URL` must be set. If a customer supplies `PIPELINES_GRUNTWORK_READ_TOKEN` as a
CI variable, it is used as-is and never refreshed.
