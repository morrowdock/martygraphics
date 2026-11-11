# Security policy

This is an early preview. Only the latest release and the latest commit on `main` are
considered for security fixes. There is no security support SLA.

Report vulnerabilities privately to [hello@morrowdock.app](mailto:hello@morrowdock.app),
the security contact for this project, or use GitHub's private vulnerability reporting:
**Security** tab, then **Report a vulnerability**.

Include the affected commit or release, the impact, a minimal reproduction with
synthetic data only, and how we can reply to you. Do not post vulnerabilities,
secrets, personal data or private course material in public issues. Never include
real credentials in a report. We coordinate disclosure with you after a fix is
available.

## In scope

- The parsers and checkers: a document that crashes the process, hangs it, or uses
  memory without bound despite the documented limits (`MGLimits`, `MGLessonLimits`,
  the solid format limits).
- A document that the strict check accepts although a documented rule says it must
  be refused.
- The tools in this repository (`marty-solid`, `marty-scene-validate`, the scripts in
  `tools/`), for example a path that writes outside its output directory.

## Out of scope

- Factual errors in the text of a document. The engine does not check what words
  mean; open an ordinary issue.
- The Marty agent and its MCP server. Report those to
  [morrowdock/marty](https://github.com/morrowdock/marty/blob/main/SECURITY.md).
