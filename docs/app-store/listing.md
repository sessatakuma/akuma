# AkuMa App Store listing draft

## English

- Name: AkuMa
- Subtitle: Japanese Reading & Pitch
- Promotional text: Add furigana and pitch-accent markings to Japanese text. Explore readings, make corrections, and share your study notes.
- Keywords: Japanese,furigana,pitch,accent,reading,kana,pronunciation,study
- Suggested primary category: Education
- Support URL: https://github.com/sessatakuma/akuma/issues
- Privacy policy URL: pending publication of the approved privacy policy

### Description

AkuMa helps you study Japanese reading and pitch accent.

Paste Japanese text to see furigana and pitch-accent markings. Tap a word to
adjust its reading or pitch, preview the change, and save your corrections.
Undo and redo let you explore different readings. Your draft and completed
result stay available when you reopen the app.

Share your result as an image and readable text using the iOS share sheet.
The built-in guide explains how to read the pitch markings.

Analysis needs an internet connection. Automatically generated readings and
accent markings can require correction. AkuMa supports iPhone and iPad in
portrait, follows system appearance, and supports larger text sizes.

### Initial release notes

Japanese text analysis with furigana and pitch accents, word-level corrections,
saved sessions, undo/redo, a pitch guide, and native sharing.

## Review notes draft

No login is required. Paste Japanese text or use “Try an example,” then tap
Analyze. Tap a result word to edit its reading or accent. Analysis calls the
production AkuMa API. A network failure preserves the draft and previous result
and offers retry. The shipping build does not use screenshot fixtures.

Review contact name, email, and phone: fill in App Store Connect.

## Before submission

- Confirm the name/category/availability with the publisher.
- Publish the approved privacy policy and enter its public URL.
- Confirm App Privacy responses for submitted text, service providers, and logs.
- Complete age rating, content rights, export compliance, and review contact fields.
- Upload reviewed iPhone and iPad captures from `bun run ios:screenshots`.
- Add reviewed Japanese and Traditional Chinese listing translations if those
  App Store localizations will be offered. App UI already supports these languages.
