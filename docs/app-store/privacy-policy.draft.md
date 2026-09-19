# AkuMa iOS privacy policy — draft, not ready for publication

The policy must identify the service operator, privacy contact, upstream analysis
provider, and actual text/log retention before it is published. The repository
alone does not establish those operational facts.

## Verified app behavior to describe

- The app stores the current draft, completed analysis, reading/accent edits,
  undo/redo history, and display preferences locally through iOS UserDefaults.
- When the user requests analysis, the submitted Japanese text is sent over HTTPS
  to `akuma.sessatakuma.dev`. The server forwards the request to its configured
  upstream analysis service. The upstream API credential stays on the server.
- The user can share a result through the iOS share sheet to their chosen app or
  recipient. That destination handles the exported content under its own policy.
- The native app's current code has no account sign-in, advertising SDK, or
  third-party analytics SDK. This statement does not describe website analytics
  or infrastructure logs.

## Operator facts required to finalize the policy

- Legal/operator name and privacy contact.
- Identity and role of the upstream analysis provider and other processors.
- Whether submitted text is retained by either service, retention duration,
  purposes, deletion process, and any use beyond producing the requested result.
- Request/server log fields (including IP addresses or text), retention duration,
  and access/deletion process.
- Applicable storage locations and disclosures for the service's users.

Do not claim “no data collected,” “text is never stored,” or a retention period
until these facts have been verified. Complete App Store Connect's App Privacy
answers consistently with the approved policy and actual server/provider behavior.

The bundled `PrivacyInfo.xcprivacy` declares the required UserDefaults access
reason for local app storage and no tracking. It is not a substitute for the
public privacy policy or App Store Connect's data-collection disclosures.
