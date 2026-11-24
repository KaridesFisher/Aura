# Public source-release boundary

This repository was prepared from an explicit selection of source, test, build-helper and attributed resource files. It starts with fresh Git history rather than publishing a local workspace's history.

## Excluded material

- Keychain entries, storage keys, provider accounts and third-party service credentials.
- Local application data, catalogs, watch history, favorites, personalized preferences and guide caches.
- Diagnostic logs, stack samples, screenshots of a personal account and local validation notes.
- Build folders, dependency binaries, signed applications, distribution archives and debug symbols.
- Recordings, downloaded programs, downloaded subtitles and local synchronization files.
- Editor state, operating-system metadata and a local-only artwork preparation helper using temporary paths.

## Review performed

The publication copy is checked for known private identifiers, credentials and provider details, private filesystem paths, common token/private-key formats and unexpected files. A separate secret scanner checks the prepared files and fresh commit history. Resource metadata is inspected separately; the project banner contains only project graphics and text, and no screenshot of a real library.

Source files deliberately use platform directory APIs or portable relative paths. A generic macOS data-directory description in documentation is not an export of any computer's actual directory contents.

Only synthetic fixture credentials and public demo endpoints are intended to remain. Example media stays subject to its own attribution and licensing notices.

These checks reduce accidental disclosure within the published material. They are not a mathematical guarantee against every undiscovered secret, software vulnerability or unrelated information already visible on a GitHub profile. The scope is this source release; it does not include an export of the application binary or private local data.
