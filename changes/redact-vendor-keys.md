### Fixed
- **GitHub fine-grained, Stripe, Google and GitLab keys are now redacted.** Keys starting `github_pat_`, `sk_live_`, `rk_live_`, `sk_test_`, `rk_test_`, `AIza` or `glpat-` were sent unredacted in the session digest and the prompt-recall query; rotate any such key you pasted into a prompt before this release.
