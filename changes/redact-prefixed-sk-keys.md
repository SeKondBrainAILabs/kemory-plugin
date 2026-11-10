### Fixed
- **Anthropic and OpenAI project keys are now redacted.** Keys starting sk-ant-, sk-proj- or sk-svcacct- were sent unredacted in the session digest and the prompt-recall query; rotate any such key you pasted into a prompt before this release.
