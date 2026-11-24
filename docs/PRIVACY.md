# Privacy and data flow

This document describes the source release. It does not promise that every future modification or third-party build behaves identically.

## Local account and library storage

Provider usernames/passwords, optional service credentials and the storage encryption key use macOS Keychain. Catalog, preference, guide, transfer-task and personal-library files are stored with AES-GCM encryption in the application's standard Application Support directory. An application update or quit does not intentionally erase them.

Downloaded video, recordings and subtitle files are ordinary local media files, not automatically encrypted by this storage mechanism. The operating system, local account permissions and any device encryption also matter.

## Network destinations

Aura contacts the provider or playlist/guide addresses you configure. Those providers receive the account information required by their protocols; a provider using HTTP rather than HTTPS does not gain transport encryption from Aura. System HTTPS certificate validation remains enabled.

Artwork URLs and public demo streams contact their respective hosts. OpenSubtitles and Trakt receive requests only through their corresponding integrations when used; Trakt can receive viewing information when connected and enabled. These are independent services with their own policies. No developer-operated analytics or telemetry endpoint is configured in this source release.

## Optional folder synchronization

Folder synchronization writes a personal-library JSON containing favorites, watch progress, custom display names and category preferences to the folder selected by the user. Aura does not separately encrypt that JSON. The folder's sync provider and anyone with access to the folder may be able to read it. Provider account passwords are not included in the synchronized JSON.

## Public repository boundary

The source repository contains implementation code, synthetic test fixtures, artwork and attributed demo media. It does not contain a user's Keychain database, encryption key, provider account, API token, personal library, recordings, downloads or diagnostic captures from a personal computer. Those files are not necessary to compile the source.

The repository owner's public GitHub handle is visible in the project URL. Publication commits use a project-only author identity rather than a personal email address. GitHub still records ordinary repository metadata, including commit times; these are not an export of device settings or account data.

## Reporting safely

Never post a complete Xtream URL containing a password, an API key, authentication token, account export or personal viewing-history file in a public issue. Replace identifying values before sharing reproduction steps. See [SECURITY.md](../SECURITY.md).
