# Commit conventions

- Use **Conventional Commits** format for all commit messages (e.g. `feat(clrepo): ...`, `fix(clrepo): ...`).
- When committing any change to `shell/clrepo.sh`, bump `_CLREPO_VERSION` (defined near the top of the file) according to semver: patch for fixes, minor for new features, major for breaking changes.
