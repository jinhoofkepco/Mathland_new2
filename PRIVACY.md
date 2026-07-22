# MathLand privacy

MathLand is designed for a family to use without advertising, tracking, or a child account. This document describes the data behavior of the open-source preview build.

## Data kept on the child device

The app stores the child nickname, a locally protected four-digit PIN verifier, accessibility and game settings, earned rewards, activity progress, resume checkpoints, a random app/device identifier, and an append-only learning-event journal. The journal records activity IDs, generated-question parameters, submitted and correct answers, correctness, response duration, health and reward changes. It does not request a legal name, email address, birth date, location, contacts, camera, microphone, advertising ID, or photos.

Local data remains on the device until the profile is deleted, app data is cleared, or the app is uninstalled. Offline play continues to append events locally.

## Optional family cloud synchronization

Cloud synchronization is off when no valid public Supabase configuration is bundled. When a guardian explicitly pairs a profile with a one-time code, the app may send the local profile identifier, random device identifier, learning events, rewards, and last-sync time to the configured family Supabase project. A short-lived access token is held only in memory; the refresh token is stored through Android Keystore-backed secure storage when that plugin is available.

The guardian dashboard reads only families to which the signed-in guardian has an active membership. Row-level security and server-side pairing/ingestion boundaries are part of the repository. A service-role key or AI-provider key must never be placed in the APK or browser bundle.

The preview Pages dashboard uses clearly synthetic demo data unless an operator deliberately deploys it with a live project configuration. Demo actions do not contain or upload a real child's information.

## Voice, analytics, and AI

The Korean guide voice is a bundled synthetic voice asset. MathLand does not record or upload the child's voice. The project includes no advertising SDK, behavioral analytics SDK, crash-tracking SDK, or cross-app tracker.

Optional AI assistance is limited to drafting adult-authored activity content on a server-controlled boundary. Child learning events, nicknames, tokens, and family records must not be sent to an AI provider.

## Guardian controls and retention

The guardian interface includes family export, device disconnect, and child-profile deletion boundaries. A deployed operator is responsible for applying the included migrations, configuring retention and backups, and honoring export or deletion requests. Deleting a cloud profile removes its learning events through the audited database procedure; deleting cloud data does not silently delete a child's offline device copy.

Do not post personal or child data in a public issue. For privacy questions, open a metadata-only repository issue or contact the repository owner through GitHub.
