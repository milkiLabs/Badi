# CI/CD

A GitHub Actions workflow automatically builds a release-optimized binary
whenever a version tag is pushed. The workflow lives at
`.github/workflows/release.yml`.

## Trigger

Any tag matching `v*` starts the workflow:

```bash
git tag v1.0.0
git push --tags
```
