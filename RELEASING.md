# Releasing Kicho

Kicho uses semantic versioning. Prerelease identifiers are used while a new
minor release is receiving CI and real-project validation.

The current development version is `0.2.0-alpha.1`. The next planned release is
`0.2.0-alpha.2`, containing compatibility fixes found through representative
project use. After that prerelease is confirmed on active English and Japanese
projects, freeze the command names and primary output formats before promoting
Kicho to `0.2.0-beta.1`.

## Release Checklist

1. Start from a clean `main` branch synchronized with the remote.
2. Update `KICHO_VERSION` in `lib/kicho/common.sh`.
3. Update version assertions in the integration tests.
4. Move completed user-visible changes into a dated CHANGELOG section.
5. Run the supported compatibility suite:

   ```bash
   KICHO_TEST_BASH=/bin/bash /bin/bash tests/run.sh
   ```

6. Commit and push the release preparation.
7. Confirm the macOS GitHub Actions workflow succeeds.
8. Create an annotated `vVERSION` tag and push it:

   ```bash
   git tag -a vVERSION -m "Kicho vVERSION"
   git push origin vVERSION
   ```

9. Create the corresponding GitHub release from the CHANGELOG entry.

Do not tag a release when the work tree is dirty or the required CI workflow is
failing.
