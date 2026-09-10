# NOVA — Native On-Device & Frontier AI Assistant for iOS

[![iOS Build & Compile Validation](https://github.com/ccebin/NOVA/actions/workflows/ios-build.yml/badge.svg)](https://github.com/ccebin/NOVA/actions/workflows/ios-build.yml)
[![Platform](https://img.shields.io/badge/Platform-iOS%2018.0%2B-blue.svg)](https://apple.com/ios)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-16.0%2B-1575F9.svg)](https://developer.apple.com/xcode)
[![Free Tier Only](https://img.shields.io/badge/Gemini-Free%20Tier%20Enforced-green.svg)](https://ai.google.dev)

NOVA is a personal AI assistant built for iPhone and iPad in **pure SwiftUI**. It implements the **ONE NOVA ASSISTANT** architecture: a unified brain sharing context, persistent memory, personality, and device action verification across multiple interchangeable inference engines.

---

## Architecture: ONE NOVA

```
                          ┌───────────────────────────┐
                          │   USER PROMPT / AUDIO     │
                          └─────────────┬─────────────┘
                                        │
                         ┌──────────────▼──────────────┐
                         │      NOVA UNIFIED BRAIN     │
                         │  - MemoryManager (Shared)   │
                         │  - NovaPersonality ("NOVA") │
                         │  - ConversationContext      │
                         │  - AdaptiveReasoningEngine  │
                         └──────────────┬──────────────┘
                                        │
                         ┌──────────────▼──────────────┐
                         │   InferenceEngineRouter     │
                         │    (.auto / .gemini /       │
                         │          .smolLM2)          │
                         └──────┬───────────────┬──────┘
                                │               │
              ┌─────────────────▼──┐       ┌────▼─────────────────┐
              │ Gemini 3.8 Flash   │       │ SmolLM2-360M Core ML │
              │ (Free Tier Cloud)  │       │ (Offline On-Device)  │
              └─────────┬──────────┘       └────┬─────────────────┘
                        │                       │
                        │ Fallback on Quota/    │
                        │ Network Failure       │
                        └───────────────────────┤
                                                │
                                   ┌────────────▼────────────┐
                                   │ GenericToolRouter       │
                                   │ ToolExecutor            │
                                   │ State Diff Observation │
                                   │ VerificationGate        │
                                   └────────────┬────────────┘
                                                │
                                   ┌────────────▼────────────┐
                                   │ VERIFIED RESULT / SPEECH│
                                   └─────────────────────────┘
```

---

## Key Capabilities & Invariants

### 1. Multi-Engine Inference Routing
* **`.auto` Mode**: Queries **Gemini 3.8 Flash** when connected. If network drops or Free Tier quota/rate limits are encountered, NOVA transparently falls back to on-device **SmolLM2-360M Core ML** with clear UI status (`Gemini unavailable (quotaExceeded) → SmolLM2 fallback`).
* **`.gemini` Mode**: Strictly frontier cloud intelligence. Surfaces real errors directly without silent fallback.
* **`.smolLM2` Mode**: 100% offline, airplane-mode capable, on-device intelligence using Core ML 8 stateful operations. Zero network packets transmitted.

### 2. Google Gemini Free Tier Enforced
* **Text Intelligence**: `gemini-3.8-flash` via official Google AI Studio REST endpoints with native `thinking_level` configuration.
* **Realtime Voice**: `gemini-3.1-flash-live-preview` over bidirectional WebSockets (`BidiGenerateContent`).
* **Audio Contracts**: 16-bit Linear PCM, 16 kHz Mono input; 16-bit Linear PCM, 24 kHz Mono output. Setup handshake (`setupComplete`) strictly gates audio streaming.
* **Zero Billing**: No code exists for automated billing, payment method configuration, or pay-as-you-go activation. Quota exhaustion (HTTP 429 / `RESOURCE_EXHAUSTED`) is gracefully handled.

### 3. Verification Gate (No Hallucinated Actions)
Gemini's verbal assertions ("I scheduled your meeting", "I created your reminder") are **never accepted as success**. Actions execute strictly through:
$$\text{NOVA} \longrightarrow \text{ToolExecutor} \longrightarrow \text{EventKit Action} \longrightarrow \text{State Diff} \longrightarrow \text{VerificationGate}$$
If an action cannot be verified in the device database, the assistant explicitly reports an unverified caution notice.

### 4. Zero Plaintext Security
* API keys are isolated in Apple's **Keychain** (`Security.framework` with `kSecClassGenericPassword` and device-only accessibility).
* Zero plaintext secrets in `UserDefaults`.
* REST calls authenticate using the official `x-goog-api-key` HTTP header (no URL query parameter leaks).
* UI strictly displays masked keys (`AIza••••••••XXXX`).

---

## Project Structure

```
├── .github/workflows/
│   └── ios-build.yml           # GitHub Actions macOS runner Xcode compile validation
├── Nova.swiftpm/               # Apple Swift Playgrounds Application Package
│   ├── App/                    # App entry point (NOVAApp) and AppState coordinator
│   ├── Core/
│   │   ├── AI/                 # AIProvider protocols, Gemini, SmolLM2, Agent Loop
│   │   │   ├── Gemini/         # GeminiProvider, GeminiLiveProvider, Keychain key provider
│   │   │   ├── SmolLM2/        # Core ML 8 stateful MLProgram, tokenizer, sampler
│   │   │   └── AgentLoop/      # AgentToolExecutionLoop, VerificationGate
│   │   ├── Capabilities/       # On-device hardware & framework diagnostics
│   │   ├── Intelligence/       # ContextBuilder, NovaPersonality, MemoryManager
│   │   ├── Persistence/        # SwiftData storage & explicit memory extraction
│   │   ├── Tools/              # EventKit Calendar & Reminders tools, ToolRegistry
│   │   └── Voice/              # NovaVoiceManager (AVSpeechSynthesizer, SFSpeechRecognizer)
│   ├── UI/                     # Native SwiftUI design system, NovaOrb, Chat, Settings
│   └── Package.swift           # Swift Package Manager manifest (.iOSApplication)
├── PHASE7_DEVICE_TEST.md       # On-Device SmolLM2 Core ML test runbook
├── PHASE8_DEVICE_TEST.md       # Real Gemini API & Gemini Live test runbook
└── scripts/
    └── validate_project.py     # Local Linux static & bracket validation tool
```

---

## Running & Installing on iPhone (No Mac Required)

Because NOVA is structured as an official Apple Swift Playgrounds application package (`Nova.swiftpm`), **you do not need a Mac to install it on your physical iPhone**:

1. Install **Swift Playgrounds 4.5+** from the App Store on your iPhone 13 Pro (running iOS 18.0+).
2. Download or AirDrop the `Nova.swiftpm` folder to the **Files** app on your iPhone.
3. Open `Nova.swiftpm` inside Swift Playgrounds.
4. Tap **App Settings** $\to$ choose your personal Apple ID $\to$ tap **Install on this iPhone**.
5. Apple will sign the app directly on your device for free.

---

## Verification & Testing

To run the deterministic verification suite on Linux:
```bash
python3 scripts/validate_project.py
```

To run the in-app verification suites on your iPhone:
Navigate to **Settings** $\to$ **Run Tool Verification Suite**:
* **Phase 3**: 13/13 Local Tools & EventKit Tests
* **Phase 4**: 10/10 Agent Loop & Decision Provider Tests
* **Phase 5**: 14/14 Intelligence Core & Memory Tests
* **Phase 6**: 18/18 Native Voice & Audio Tests
* **Phase 7**: 22/22 SmolLM2 Core ML & Tokenizer Tests
* **Phase 8**: 20/20 Gemini REST, Live & Security Tests
