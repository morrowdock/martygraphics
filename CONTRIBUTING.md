# Contributing

Small bug reports and focused pull requests are welcome during this early preview.
Explain the behavior, provide a synthetic reproduction, and run the checks in README.md.
Use original synthetic fixtures and document changes to the public format.
Do not submit personal data, course-derived material, generation instructions,
private adapters, credentials, or proprietary templates.

Every commit must include a DCO sign-off. By signing, you certify the
[Developer Certificate of Origin 1.1](https://developercertificate.org/).
Use `git commit -s` and an email you are comfortable publishing; a GitHub noreply
address is recommended. A sign-off is a certification, not a cryptographic signature.

Every pull request must pass the required `CI` check runs `hygiene` (whitespace,
tool tests, DCO, file manifest) and `macos` (hosted build and Swift tests). They run
automatically on each push to the PR; a fork PR runs with a read-only token and
no secrets. Branch protection also requires the branch to be up to date with
`main` before merging, because the checks test the PR head itself, not a
synthetic merge; update the branch when GitHub asks. `main` takes only squash
merges. On a push to `main` whose previous commit is unknown (for example a new
branch or a rewritten history), the `hygiene` DCO step checks only the last
commit, so it can miss a missing sign-off on earlier commits of a multi-commit
push. This is acceptable only because `main` takes squash merges of reviewed
PRs, force pushes are disabled, and the rules include administrators. Hosted runners have no real GPU, so local GPU and iOS-simulator
receipts are still required where [Verify on Mac](docs/VERIFY-ON-MAC.md) and
[local validation](docs/LOCAL-VALIDATION.md) ask for them.

Follow CODE_OF_CONDUCT.md. Report vulnerabilities using SECURITY.md.
