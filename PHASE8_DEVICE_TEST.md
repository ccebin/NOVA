# NOVA — PHASE 8.1 PHYSICAL DEVICE & REAL GEMINI API TEST RUNBOOK

> **Target Device**: iPhone 13 Pro (A15 Bionic, 6 GB Unified LPDDR4X RAM)  
> **Target OS**: iOS 18.0 or later (Required for Core ML 8 `MLState` + Gemini Live Audio)  
> **Frontier Text Engine**: Google Gemini 3.8 Flash (`gemini-3.8-flash` via Google AI Studio Free Tier)  
> **Realtime Voice Engine**: Google Gemini 3.1 Flash Live (`gemini-3.1-flash-live-preview` via WebSockets)  
> **On-Device Offline Engine**: Standalone Core ML 8 (`SmolLM2-360M-Instruct-4bit.mlmodelc`)  
> **Billing Policy**: STRICTLY FREE TIER ONLY (Zero automated billing or pay-as-you-go)  

---

## EXECUTIVE PRE-TEST CHECKLIST

Before beginning the physical verification procedure on your iPhone:
- [ ] iPhone 13 Pro running iOS 18.0+ (Check in `Settings > General > About`).
- [ ] Internet Connection: Active Wi-Fi or Cellular data enabled (required for Gemini Cloud REST & Live WebSockets).
- [ ] Valid Google Gemini API Key from Google AI Studio (Starts with `AIzaSy...`).
- [ ] Low Power Mode **OFF** (to ensure standard Neural Engine and Network performance).
- [ ] Microphone permission granted for NOVA in iOS Settings.

---

## SECTION 1: GEMINI API KEY SETUP (KEYCHAIN ISOLATION)

1. Launch **NOVA** on your iPhone.
2. Tap the **Settings** gear icon in the top right.
3. Scroll to **Google Gemini Free Tier (Phase 8)**:
   - Notice the footer: *"Free Tier Only: gemini-3.8-flash (Text) and gemini-3.1-flash-live-preview (Voice). Zero automatic billing or paid plans. Secret keys are never stored in plaintext UserDefaults."*
4. In the secure field, paste your Gemini API key (`AIzaSy...`).
5. Tap **Save to Keychain**.
6. Verify:
   - The field collapses and displays the masked key: `AIza••••••••XXXX`.
   - Plaintext key is nowhere visible in the interface.
   - Key is stored exclusively in Apple's secure Keychain (`kSecClassGenericPassword`).

---

## SECTION 2: REAL GEMINI TEXT TEST (TURKISH & ENGINE VERIFICATION)

1. Return to the main conversation view in NOVA.
2. In Settings, verify **Engine Selection** is set to `Auto: Gemini Flash (SmolLM2 Fallback)` or `Gemini 3.8 Flash (Cloud Only — Free Tier)`.
3. Send the exact verification prompt:
   > *"Merhaba NOVA. Bana kendini kısaca tanıt ve şu an hangi inference engine'i kullandığını söyle."*
4. **Observe & Verify**:
   - [ ] Prompt sends over HTTPS to `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent`.
   - [ ] Orb transitions to Thinking (`.thinking`), then Responding (`.responding`).
   - [ ] Response is received in natural, fluent Turkish.
   - [ ] Response identifies NOVA by name (NOVA Personality applied).
   - [ ] Response explicitly indicates it is running on **Gemini 3.8 Flash** via cloud intelligence.
   - [ ] Message history updates in SwiftData (`LocalDataManager`).
   - [ ] Memory extraction operates normally if explicit facts are mentioned.

---

## SECTION 3: MULTI-ENGINE SWITCH TEST (CONVERSATION INVARIANCE)

1. In the ongoing conversation, say:
   > *"Benim adım Ali ve en sevdiğim renk lacivert."*
2. Confirm NOVA acknowledges: *"Noted. I'll remember that..."*.
3. Go to **Settings** $\to$ **Engine Selection** $\to$ Select `SmolLM2-360M-Instruct (Core ML)`.
4. Return to the conversation and ask:
   > *"Benim adım ne ve en sevdiğim renk neydi?"*
5. Confirm SmolLM2 retrieves the memory from `MemoryManager` and answers correctly.
6. Go back to **Settings** $\to$ **Engine Selection** $\to$ Switch back to `Gemini 3.8 Flash`.
7. Ask a follow-up question:
   > *"Bu rengin yanına hangi renk iyi gider?"*
8. **Verify Invariants**:
   - [ ] Conversation history remained 100% intact across the 3 engine switches.
   - [ ] Memory was not wiped or duplicated.
   - [ ] NOVA's personality and tone remained consistent.
   - [ ] Zero duplicate assistant instances created.

---

## SECTION 4: REAL DEVICE TOOL + VERIFICATION GATE TEST

1. In conversation with Gemini active, request a real device action:
   > *"Yarın sabah saat 09:00 için 'Doktor randevusu' hatırlatıcısı oluştur."*
2. **Observe Execution Chain**:
   - Gemini emits a function call for `reminders.create` with argument `title: "Doktor randevusu"`.
   - `GenericToolRouter` matches the definition in `ToolRegistry`.
   - `ToolExecutor` prompts for confirmation and executes via Apple `EventKit`.
   - `VerificationGate` inspects EventKit database before and after execution.
   - If verified in EventKit: Assistant responds with verified checkmark (`✓ Create Reminder successfully verified on your iPhone`).
3. **Negative / Unverified Test**:
   - Go to iOS Settings $\to$ NOVA $\to$ Revoke Reminders permission.
   - Repeat the request.
   - Even if Gemini says "I created it", verify `VerificationGate` catches the failure and displays:
     > *"Notice: The requested action could not be verified on your device. Details: Calendar/Reminders access denied by system."*
   - [ ] Verbal claim without device proof is strictly rejected!

---

## SECTION 5: REAL QUOTA & OFFLINE FALLBACK TEST

### Test 5A: Airplane Mode Fallback (`.auto` policy)
1. In Settings, ensure **Engine Selection** is `Auto: Gemini Flash (SmolLM2 Fallback)`.
2. Swipe down Control Center and enable **Airplane Mode** (disable Wi-Fi and Cellular).
3. Send a message: *"Saat kaç?"*.
4. **Verify**:
   - Gemini request fails with `networkUnavailable`.
   - NOVA automatically routes the turn to on-device `SmolLM2Provider`.
   - Status banner appears: `Gemini unavailable (networkUnavailable) → SmolLM2 fallback`.
   - Conversation is NOT aborted.
5. Disable Airplane Mode. Next message returns to Gemini 3.8 Flash automatically.

### Test 5B: Strict Mode (`.gemini` policy)
1. In Settings, change **Engine Selection** to `Gemini 3.8 Flash (Cloud Only)`.
2. Enable Airplane Mode.
3. Send a message: *"Merhaba"*.
4. **Verify**:
   - NOVA surfaces the actual error: `Notice: Network Unavailable...`.
   - NOVA does NOT fall back to SmolLM2.

---

## SECTION 6: REAL GEMINI LIVE REALTIME VOICE TEST

1. In Settings, under **Voice Pipeline**, select `Gemini 3.1 Flash Live (Realtime WebSocket Voice)`.
2. Tap the Nova Orb or microphone button to initiate voice session.
3. **Observe Lifecycle**:
   - [ ] WebSocket connects to `wss://generativelanguage.googleapis.com/...` with `gemini-3.1-flash-live-preview`.
   - [ ] Handshake: NOVA sends `setup` payload with `Aoede` voice configuration.
   - [ ] Sunucu `setupComplete` dönene kadar mikrofon ses paketi GÖNDERİLMEZ.
   - [ ] Orb transitions from `.thinking` to `.listening`.
4. Speak in Turkish: *"Merhaba NOVA, beni duyabiliyor musun?"*.
5. Audio Input: 16-bit PCM, 16 kHz, Little-Endian, Mono streamed to WebSocket.
6. Audio Output: 16-bit PCM, 24 kHz, Little-Endian, Mono received from `modelTurn.parts.inlineData`.
7. Realtime speech plays clearly through iPhone speaker.

---

## SECTION 7: BARGE-IN (INTERRUPTION) TEST

1. While NOVA is actively speaking through Gemini Live, speak loudly:
   > *"NOVA dur, bir saniye!"*
2. **Verify**:
   - Gemini Live server detects user speech and emits `serverContent.interrupted: true`.
   - iPhone audio playback buffer is instantly cleared.
   - NOVA stops talking immediately.
   - Session transitions back to `.listening` and receives the new user instruction.

---

## SECTION 8: PERFORMANCE MEASUREMENTS (XCODE / INSTRUMENTS)

Record actual values measured on the iPhone 13 Pro (do not estimate):

| Metric | Target / Benchmark | Physical Measurement |
| :--- | :--- | :--- |
| **Gemini 3.8 First-Token Latency** | $< 800\text{ ms}$ (Wi-Fi) | `__________ ms` |
| **Gemini 3.8 Streaming Token Rate** | $> 30\text{ tokens/sec}$ | `__________ tok/s` |
| **Gemini Live Setup Handshake** | $< 500\text{ ms}$ | `__________ ms` |
| **Gemini Live Audio Round-Trip** | $< 1200\text{ ms}$ | `__________ ms` |
| **SmolLM2 Cold Start (Core ML)** | $< 1500\text{ ms}$ | `__________ ms` |
| **SmolLM2 Warm TTFT (Core ML)** | $< 350\text{ ms}$ | `__________ ms` |
| **Resident RAM (Gemini Mode)** | $< 150\text{ MB}$ | `__________ MB` |
| **Resident RAM (SmolLM2 Active)** | $< 650\text{ MB}$ | `__________ MB` |
| **Cancellation Latency** | $< 50\text{ ms}$ | `__________ ms` |

---

## SECTION 9: VERIFICATION CHECKLIST & FINAL SIGN-OFF

Run the in-app test suite in **Settings $\to$ Run Tool Verification Suite**:
- [ ] Phase 3: 13/13 Verified Local Tools Tests PASS.
- [ ] Phase 4: 10/10 Agent Loop Tests PASS.
- [ ] Phase 5: 14/14 Intelligence Core Tests PASS.
- [ ] Phase 6: 18/18 Native Voice Tests PASS.
- [ ] Phase 7: 22/22 SmolLM2 Core ML Tests PASS.
- [ ] Phase 8: 20/20 Gemini REST, Live & Security Tests PASS.
