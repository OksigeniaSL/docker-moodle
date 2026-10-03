# Security policy

## Supported images

Only the tags of Moodle branches that still receive security fixes from Moodle HQ are rebuilt. Every supported branch is rebuilt weekly with the latest Debian and PHP fixes, and as soon as Moodle publishes a new point release.

## Reporting a vulnerability

- **In the image** (the Dockerfile, the entrypoint scripts, the default configuration): report it privately through [GitHub security advisories](https://github.com/OksigeniaSL/docker-moodle/security/advisories/new). Please do not open a public issue. We aim to answer within five working days.
- **In Moodle itself:** report it to Moodle HQ through the [Moodle security process](https://moodledev.io/general/development/process/security).
- **In Oksigenia Access:** report it in its [repository](https://github.com/OksigeniaSL/moodle-local_oksigeniaaccess/security/advisories/new).

## Verifying images

Images are signed with cosign (keyless, GitHub OIDC) and carry SBOM and provenance attestations. See the README for the verification commands.
