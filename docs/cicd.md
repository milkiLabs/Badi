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

## What it does

1. Checks out the repository.
2. Installs Zig via [mlugg/setup-zig@v2](https://codeberg.org/mlugg/setup-zig)
   with `version: latest` (latest stable release).
3. Runs `zig build -Doptimize=ReleaseFast`.
4. Uploads the contents of `zig-out/` as a downloadable artifact named after
   the tag (e.g., `release-v1.0.0`).

## Downloading the artifact

After the workflow completes:

1. Go to the repository's **Actions** tab.
2. Select the completed workflow run.
3. Under **Artifacts**, download the zip for your tag.

## Zig version

The workflow uses `version: latest` to always pull the latest stable Zig
release. To pin a specific version, change it in the workflow:

```yaml
- uses: mlugg/setup-zig@v2
  with:
    version: 0.13.0
```

If you leave `version` empty, the action reads `minimum_zig_version` from
`build.zig.zon` and falls back to `latest`. This project currently requires
Zig 0.16.0, but mirrors may not yet carry nightly/dev builds — using
`latest` is the safest option.

## Customization

- **Zig version** — change the `version` field in the `mlugg/setup-zig@v2` step.
- **Mirror** — set `mirror` to use a specific mirror (avoid hammering one):
  ```yaml
  - uses: mlugg/setup-zig@v2
    with:
      mirror: 'https://pkg.machengine.org/zig'
  ```
- **Build output path** — update the `path` in the `upload-artifact` step if
  your project writes output elsewhere.
- **Additional build steps** — add steps before the upload to run tests,
  generate checksums, or create a GitHub Release with the artifact attached.
