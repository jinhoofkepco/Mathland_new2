# Scheduled content activation

Pending Content Studio publications need a trusted server-side invocation after
their UTC `effective_at`. The `activate-publications` Edge Function drains one
bounded due batch and delegates every transition to the idempotent database
activation RPC. Do not call this endpoint from the web app or Android app.

## One-time deployment

Requirements:

- an authorized Supabase CLI session for the intended project;
- a scheduler capable of an HTTPS `POST` at least every five minutes;
- a randomly generated scheduler secret of at least 32 characters.

Generate the secret in a protected operator shell and store it directly as a
Supabase function secret. Never paste the value into chat, logs, repository
files, GitHub Pages variables, or the Android build.

```sh
MATHLAND_NEW_SCHEDULER_SECRET="$(openssl rand -base64 48)"
supabase secrets set \
  MATHLAND_SCHEDULER_SECRET="$MATHLAND_NEW_SCHEDULER_SECRET" \
  --project-ref YOUR_PROJECT_REF
supabase functions deploy activate-publications \
  --no-verify-jwt \
  --project-ref YOUR_PROJECT_REF
unset MATHLAND_NEW_SCHEDULER_SECRET
```

The deployed runtime also receives `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY` from Supabase. It deliberately does not require the
browser publishable key, a CORS allowlist, or pairing secrets.

Configure the trusted scheduler with the same secret in its own protected
secret store. Send a JSON body and no browser `Origin` header:

```sh
curl --fail-with-body --silent --show-error \
  --request POST \
  "https://YOUR_PROJECT_REF.supabase.co/functions/v1/activate-publications" \
  --header "Authorization: Bearer $MATHLAND_SCHEDULER_SECRET" \
  --header "Content-Type: application/json" \
  --data '{"batchLimit":25}'
```

`batchLimit` defaults to 25 and must be an integer from 1 through 100. A success
response is shaped like this:

```json
{"processed":2,"publicationIds":["PUBLICATION_UUID_1","PUBLICATION_UUID_2"]}
```

Schedule the call at least every five minutes. A single invocation processes
one batch; a large backlog drains over successive invocations. The scheduler
should retry network failures and HTTP `503` responses. Do not retry `400`,
`401`, or `405` until configuration has been corrected.

## Verification and monitoring

After deployment:

1. Call without `Authorization` and confirm HTTP `401` with
   `scheduler_auth_invalid`.
2. Call with the protected secret and `{}`; confirm HTTP `200`, even when
   `processed` is zero.
3. Schedule a synthetic publication a few minutes ahead. After its effective
   time, confirm Content Studio history shows it as active and the prior active
   version as retired.
4. Review Edge Function failures and `content_publication_activated` or
   `content_publication_cancelled` audit facts. Alert when valid scheduler calls
   fail repeatedly or a due backlog persists beyond two scheduler intervals.

The database activation is safe under concurrent or repeated delivery. A retry
may select the same publication, but the activity lock and publication status
prevent a second transition or duplicate audit fact.

## Rotation and recovery

To rotate the scheduler credential, generate a new value, update the Supabase
secret, redeploy the function, and then update the scheduler's protected value.
Pause scheduled calls during this short sequence; verify one authenticated call
before resuming. Remove the old value from the scheduler after success.

If the worker has been unavailable, restore its secret/deployment and invoke it
repeatedly with `batchLimit:100` until `processed` is zero. Do not update pending
or active publication rows directly. If one publication cannot transition,
preserve the request ID from the response header and inspect server-side logs;
the public error deliberately omits database detail.
