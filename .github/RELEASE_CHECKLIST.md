# Release Checklist

- Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` if needed.
- Run `swift test`.
- Run a clean Xcode build.
- Confirm the app icon and menu bar behavior look correct.
- Verify launch at login still works.
- Verify an automatic test still runs after sleep/wake.
- Tag the release with `vX.Y.Z`.
- Upload the zipped `.app` artifact to GitHub Releases.
- If signing secrets are configured, confirm notarization and stapling succeeded.
- Download the release artifact on a clean Mac and verify Gatekeeper acceptance.
