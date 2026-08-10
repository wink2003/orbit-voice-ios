# Orbit Voice (Phase 1)

Separate lightweight iOS client for the existing Orbit `/api/voice` endpoint.

This project is intentionally independent from `apps/orbit-voice-ios` (the
existing LiveKit client). It uses only public Apple APIs: SwiftUI,
`SFSpeechRecognizer`, `AVAudioEngine`, `AVAudioPlayer`, and `URLSession`.

The app pairs with the existing `/api/devices/pair` endpoint, keeps one
`session_id` for the whole conversation, sends turn requests to `/api/voice`,
plays the returned MP3, and starts listening again after playback.

Bundle identifier: `net.opik.orbit.voice.phase1`.
