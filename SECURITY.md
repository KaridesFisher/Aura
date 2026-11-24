# Security

## Scope

This experimental source release has no dedicated security-response service or guaranteed response time. No service credentials are bundled. Treat provider accounts, API keys, sync files and stream URLs as sensitive.

## Reporting a concern

If GitHub private vulnerability reporting is enabled for the repository, use that channel. Otherwise, start with a minimal, non-sensitive issue requesting a private reporting channel. Do not publish credentials, account exports, exploit payloads containing real user data or unredacted logs.

Include the affected source area, a description of the impact and reproduction steps using generated data. Do not test against someone else's provider account or device without authorization.

## Contributor requirements

Keep application state, build products, dependency binaries and local diagnostics outside Git. Inspect the staged diff and run a secret scanner before pushing. Never disable certificate verification or move account credentials into source to make an integration easier to test.
