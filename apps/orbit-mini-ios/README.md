# Orbit Voice iOS app

Native SwiftUI client for the self-hosted Orbit LiveKit agent.

## User flow

1. Install the unsigned `Orbit-Voice.ipa` with AltStore Classic.
2. Enter a six-digit, single-use pairing code.
3. The app stores its revocable device token in iOS Keychain.
4. Opening Orbit automatically starts an interruptible voice session.
5. Siri can open the app with "Start Orbit".

The LiveKit API secret and model credentials remain on the Hetzner server.

## Free build

The repository workflow `.github/workflows/build-orbit-voice-ios.yml` builds an unsigned IPA on a GitHub-hosted macOS runner. AltStore signs it with the device owner's free Apple Personal Team. Apple requires that signature to be refreshed at least once every seven days.

No Apple Developer Program membership is required for this workflow.
