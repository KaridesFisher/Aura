# Contributing

Aura is an early-stage native macOS project. Small, focused changes with clear reproduction steps are welcome.

1. Build and run the existing core checks with `./Scripts/check.sh`.
2. Describe the problem, expected behavior and relevant verification in your change.
3. For playback changes, distinguish decoding, frame presentation and network buffering. A growing forward cache is not a measurement of broadcast latency.
4. Use synthetic accounts or public demo media for fixtures. Never commit credentials, personalized catalogs, watch history, recordings, private paths or diagnostic captures containing account details.
5. Preserve existing account and library formats when changing persistence. Do not reset user data as a migration strategy.
6. Keep the project licensed under GPL-3.0-or-later and preserve third-party notices.

The unresolved macOS menu/title-bar frame-drop issue is documented in the README. A playback fix should include a reproducible before/after measurement rather than a claim based only on a successful build.
