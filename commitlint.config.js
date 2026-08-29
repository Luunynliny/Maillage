// Conventional Commits, checked on both the PR title and every commit in the PR.
//
// The PR title is the one that decides releases: merges into `main` are squash-only, so the title
// becomes the single commit on `main` and the only thing `@semantic-release/commit-analyzer` reads.
//
// The type list is `config-conventional`'s default, which is also the vocabulary
// `.github/workflows/ci.yml` accepts as a branch-name prefix. Keep the two in step.
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // GitHub truncates a PR title in list views past roughly this width, and the title ends up
    // verbatim in the release notes. 100 over the default 72 leaves room for the `(#12)` that
    // squash-merging appends without the limit tripping on a title that was fine when written.
    'header-max-length': [2, 'always', 100],
  },
}
