# MathLand security

## Reporting a vulnerability

Use GitHub's private vulnerability-reporting or Security Advisory flow for this repository when available. Do not include a real child's nickname, learning records, access token, refresh token, database dump, signing key, or service-role key in an issue, pull request, screenshot, or chat transcript.

Include the affected commit/version, component, safe reproduction steps, and impact. Public issues are appropriate only after sensitive details have been removed.

## Trust boundaries

- A child's four-digit PIN protects local profile switching; it is not an online account credential and does not defend a fully compromised or rooted device.
- Android refresh credentials are stored only through the Android Keystore-backed plugin. Access tokens remain in memory. Pairing codes are one-use, time-limited, and must be stored by the server only as a keyed digest.
- The APK and browser receive only a Supabase project URL and publishable client key. Service-role, database, AI-provider, and signing secrets stay outside Git and run only in protected server or release environments.
- Database row-level security restricts guardians to active family memberships and devices to their bound profile. Edge Functions validate bearer identity and call narrowly granted service procedures.
- Learning-event ingestion is bounded, schema-validated, binding-checked, ordered, and idempotent. Invalid acknowledgements never compact the offline journal.
- Downloaded content is inactive until schema, identifier allowlists, checksums, and complete staging validation succeed; an invalid update leaves bundled content available.

## Release and dependency policy

The GitHub preview APK is explicitly a testing build signed with a development certificate. Do not treat it as a Play Store production signature. A production release requires an externally backed-up keystore, documented certificate fingerprint, protected release environment, verified source tag, and independently checked artifact checksum.

Use the pinned Godot, JDK, Android SDK, Node, npm-lock, and function-runtime versions documented in the repository. CI workflows use least-privilege permissions and must never use `pull_request_target` to execute untrusted code with secrets.

Security support applies to the latest published preview or release commit. Older builds should be upgraded before a report is evaluated unless the issue blocks upgrading.
