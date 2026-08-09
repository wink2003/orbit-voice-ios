# Orbit Voice for iOS

Native SwiftUI client for the self-hosted Orbit family assistant. The app connects an iPhone directly to Orbit's LiveKit voice room without Safari.

## What it does

- pairs an iPhone using a six-digit, single-use code;
- stores a revocable device token in iOS Keychain;
- starts an interruptible voice session when Orbit opens;
- exposes App Intents so Siri and Shortcuts can open Orbit;
- keeps LiveKit credentials and AI model keys on the server.

## Repository layout

- `apps/orbit-voice-ios` — Xcode project and Swift source;
- `.github/workflows/build-orbit-voice-ios.yml` — unsigned IPA build for AltStore.

## Free installation with AltStore

1. Open the latest successful **Build Orbit Voice IPA** workflow run.
2. Download the `Orbit-Voice-IPA` artifact and unzip it.
3. Install `Orbit-Voice.ipa` with AltStore Classic.
4. Obtain a pairing code from the Orbit server administrator and enter it once.

AltStore signs the app with the iPhone owner's free Apple Personal Team. Apple requires that free signature to be refreshed at least once every seven days. A paid Apple Developer Program membership is not required.

## Privacy and security

The repository contains no LiveKit secret, AI provider key, family identifier, or permanent user credential. Pairing codes expire and can be used only once. Paired device tokens can be revoked on the Orbit server.

## License

MIT. This project is based on the LiveKit iOS voice assistant example; see [LICENSE](LICENSE).
