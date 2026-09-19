# AkuMa

A web tool for automatic Japanese furigana and accent markings to plain text, to help Japanese learners to improve their speaking and reading skills.

<img src="docs/images/demo.png" alt="AkuMa demo" />

## What It Does

- Analyzes Japanese text and renders furigana with pitch-accent markings automatically
- Lets you click the generated result to adjust furigana and accent output manually
- Supports plain-text copy, Markdown export, and image download for study notes

## How It Works

1. Paste or generate a Japanese sentence.
2. Let the app analyze and mark the text.
3. Tweak furigana or accent presentation directly in the result panel if needed.
4. Export the formatted output in the format you need.

## Quick Start (Internal Development)

Install dependencies with [bun](https://bun.com/):

```bash
bun i
```

Start the local dev server:

```bash
bun dev
```

## iOS Development

Update AkuMa on your paired iPhone (USB or wireless):

```bash
bun run iphone
```

This builds a signed app, installs it over the existing app without uninstalling,
and relaunches it. Keep your iPhone unlocked. Use `bun run ios` for the simulator.

The device script uses the Xcode project's signing team. If one isn't configured,
set `APPLE_TEAM_ID` in your environment or in a git-ignored `.env.local` file:

```dotenv
APPLE_TEAM_ID=YOUR_TEAM_ID
```

If multiple iPhones are available, select one with
`IOS_DEVICE_ID=<UDID> bun run iphone`. Find its UDID with
`xcrun devicectl list devices`. Run `bun run iphone --help` for other options.

For signed archives, TestFlight uploads, screenshots, and App Store handoff, see
[the iOS release workflow](docs/ios-release.md). Start with `bun run ios:release --help`.

## Deployment & Local Setup

Cloudflare Workers deployment, continuous deployment, routing, and the
`.env` / secrets setup live in [`docs/deployment.md`](docs/deployment.md).
