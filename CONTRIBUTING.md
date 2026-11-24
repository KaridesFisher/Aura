# Contributing

Aura is maintained by the repository owner. Repository write access is not granted automatically, and no outside collaborator is currently appointed.

## Approval required

Before starting a contribution, open an issue describing the proposed change and wait for the owner's explicit approval. A pull request is a proposal only: submitting one does not grant write access, membership, or acceptance. Only changes explicitly accepted and merged by the owner become part of this repository. Collaborator access requires a separate invitation from the owner; approval of a proposal does not grant that access.

GitHub calculates contributor attribution from accepted commit history. It is separate from repository permissions and is not a membership application system.

## Requesting collaborator access

Anyone seeking collaborator access must first open an issue titled "Collaborator access request", explain why access is needed, and wait for the repository owner's explicit approval. Do not include credentials or other private information. Access is granted only through a separate invitation issued by the owner and accepted by the applicant. Opening a request or a pull request does not grant any permissions.

## Contribution checks

For an approved proposal:

1. Build and run the existing core checks with `./Scripts/check.sh`.
2. Describe the problem, expected behavior and relevant verification in your change.
3. For playback changes, distinguish decoding, frame presentation and network buffering. A growing forward cache is not a measurement of broadcast latency.
4. Use synthetic accounts or public demo media for fixtures. Never commit credentials, personalized catalogs, watch history, recordings, private paths or diagnostic captures containing account details.
5. Preserve existing account and library formats when changing persistence. Do not reset user data as a migration strategy.
6. Keep the project licensed under GPL-3.0-or-later and preserve third-party notices.

The unresolved macOS menu/title-bar frame-drop issue is documented in the README. A playback fix should include a reproducible before/after measurement rather than a claim based only on a successful build.
