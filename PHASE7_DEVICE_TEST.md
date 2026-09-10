# NOVA — PHASE 7 PHYSICAL DEVICE TEST RUNBOOK

> **Target Device**: iPhone 13 Pro (A15 Bionic, 6 GB Unified LPDDR4X RAM, 16-core Apple Neural Engine)  
> **Target OS**: iOS 18.0 or later (Required for Core ML 8 `MLState` stateful MLProgram execution)  
> **Runtime Target**: Standalone On-Device LLM (`SmolLM2-360M-Instruct-4bit.mlmodelc`)  
> **Zero Network Guarantee**: Wi-Fi Disabled, Cellular Disabled, Zero Cloud/API Fallback  

---

## EXECUTIVE PRE-TEST CHECKLIST

Before beginning the physical verification procedure on the iPhone, verify the physical environment:
- [ ] iPhone 13 Pro running iOS 18.0+ (Check in `Settings > General > About`).
- [ ] AirPlane Mode turned **ON** (Wi-Fi and Cellular toggled completely OFF).
- [ ] Battery level $>50\%$ or device connected to a standard power source.
- [ ] Low Power Mode **OFF** (to ensure Neural Engine runs at standard performance).

---

## SECTION A: MODEL ARTIFACT SETUP

1. Obtain the verified Core ML 8 compiled package: `SmolLM2-360M-Instruct-4bit.mlmodelc` (derived from `HuggingFaceTB/SmolLM2-360M-Instruct`).
2. Verify directory contents of the `.mlmodelc` bundle:
   - `model.mil` / compiled neural graph
   - `weights/weight.bin` (~203.7 MB 4-bit quantized tensor weights)
   - `metadata.json`
   - `cstate_key_cache` / `cstate_value_cache` state schemas
3. Ensure no compression artifacts (unzip directly if transferred as an archive).

---

## SECTION B: iOS / iPadOS VERSION REQUIREMENT

- **Minimum iOS Version**: iOS 18.0 (Build 22A3354 or later).
- **Rationale**: SmolLM2 utilizes Core ML 8's stateful execution model (`MLState`). Earlier versions (iOS 17 and below) do NOT support `model.makeState()` or persistent KV-cache state tensors (`key_cache`, `value_cache` of shape `[32, 1, 5, 2048, 64]`).
- If device is running iOS 17.x, the Capability Diagnostics screen will truthfully display:
  `Stateful MLProgram: Requires iOS 18.0+`.

---

## SECTION C: SWIFT PLAYGROUNDS & XCODE SETUP

### Option 1: Xcode (Recommended for Profiling & Instruments)
1. Open `Nova.swiftpm` in Xcode 16.0+ on your Mac.
2. Select your connected iPhone 13 Pro as the run destination.
3. In `Signing & Capabilities`, configure your personal or developer Apple ID team.
4. Verify deployment target is set to **iOS 18.0**.
5. Build and install (`Cmd + R`).

### Option 2: Swift Playgrounds 4.5+ on iPad / iPhone
1. AirDrop or transfer the `Nova.swiftpm` folder to the device Files app.
2. Open `Nova.swiftpm` inside Swift Playgrounds.
3. Trust developer profile in `Settings > General > VPN & Device Management`.

---

## SECTION D: MODEL RESOURCE PLACEMENT

NOVA automatically checks two local sandboxed locations in order:

1. **Main App Bundle**:
   - In Xcode, drag `SmolLM2-360M-Instruct-4bit.mlmodelc` into the Project Navigator under `Nova.swiftpm`.
   - Target Membership: check `Nova`.
2. **App Documents Directory (Files App / iTunes File Sharing)**:
   - Connect iPhone to Mac / PC.
   - Open **Finder** (or Files app on iPhone) $\to$ Select iPhone $\to$ Files $\to$ `Nova`.
   - Create a folder named `Models` if not present.
   - Copy `SmolLM2-360M-Instruct-4bit.mlmodelc` directly into `Nova/Documents/Models/`.
   - Resulting path: `Documents/Models/SmolLM2-360M-Instruct-4bit.mlmodelc`.

---

## SECTION E: CAPABILITY DIAGNOSTICS SCREEN INSPECTION

1. Launch NOVA on the iPhone 13 Pro.
2. Navigate to `Settings` (gear icon) $\to$ `Intelligence & Runtime`.
3. Under **Engine Selection**, confirm `SmolLM2-360M-Instruct (Core ML)` is selected.
4. Tap **Capability Diagnostics** and verify the rows:
   - **Provider Selected**: `SmolLM2-360M-Instruct (Core ML)`
   - **Model Status**: Must show `MODEL_READY` (if weights are present) or `MODEL_NOT_FOUND` (if weights have not yet been placed).
   - **Model Discovered**: `Yes`
   - **Model Compiled**: `Compiled (.mlmodelc)`
   - **Model Loaded**: `Standby (Not Loaded)` (transitions to `Loaded in Memory` after turn 1)
   - **Model Path**: Verified local file path
   - **Core ML Availability**: `Available`
   - **Stateful MLProgram**: `Supported (iOS 18+)`
   - **Theoretical KV Footprint**: `83.8 MB (Buffer Only)`
   - **Live Hardware Metrics**: Displays live measured values or `NOT_VERIFIABLE_ON_CURRENT_HOST` until inference is executed.

---

## SECTION F: BASIC PROMPT TEST

### Prompt 1:
> **Input**: `"Hello, who are you?"`

- **Execution**: Type in chat or speak via native microphone.
- **Expected Behavior**:
  1. Orb transitions to `.thinking` (violet pulsing).
  2. Model prefill initializes `MLState` key/value cache.
  3. First token emits quickly (TTFT $<500$ ms on A15 ANE).
  4. Streamed output finishes cleanly with `<|im_end|>`.
  5. Orb transitions to `.responding` (amber glowing) if voice is enabled, or `.idle`.
- **Validation**:
  - Response introduces NOVA according to `NovaPersonality` guidelines.
  - Zero canned/mock tokens.

### Prompt 2:
> **Input**: `"Explain what memory means in one sentence."`

- **Expected Behavior**:
  - Direct, concise one-sentence explanation.
  - No rambling or conversational boilerplate.

---

## SECTION G: LONG GENERATION & CONTEXT TEST

### Prompt 3:
> **Input**: `"Count from 1 to 50."`

- **Evaluation Goals**:
  - Verify autoregressive token generation across at least 100+ tokens.
  - Verify KV-cache accumulates tokens sequentially without degradation or index out-of-bounds.
  - Verify sequential decode step latency remains constant throughout the loop.

### Prompt 4:
> **Input**: `"Write a short paragraph about the ocean."`

- **Evaluation Goals**:
  - Verify natural prose generation, grammar, and coherent sentence endings.
  - Verify EOS detection properly halts generation without emitting garbage tokens.

---

## SECTION H: CANCELLATION TEST

1. Send a long prompt: `"Write an extensive essay detailing the history of astronomy."`
2. While tokens are streaming rapidly across the screen, tap the **Stop/Cancel** button (or speak to interrupt if voice is enabled).
3. **Verification**:
   - Stream halts immediately.
   - Background Swift `Task` is cancelled.
   - Provider state returns to `.idle`.
   - Send follow-up prompt: `"Are you still there?"`
   - Model must respond normally without memory leaks or zombie background loops.

---

## SECTION I: STREAMING TEST

1. Enter any medium prompt.
2. Watch the chat bubble as tokens arrive.
3. **Verification**:
   - Tokens must append incrementally (not appear all at once in a bulk chunk).
   - No token re-ordering or out-of-sequence delivery.
   - No flickering or UI stuttering during rendering.

---

## SECTION J: MEMORY MEASUREMENT (RESIDENT RAM)

1. Open Xcode Instruments $\to$ **Allocations** & **VM Tracker**.
2. Measure baseline resident dirty RAM before model load ($\sim 40 - 60$ MB).
3. Trigger Prompt 1 to load model weights and initialize `MLState`.
4. Measure active resident RAM:
   - 4-bit model weights: $\sim 203.7$ MB
   - Theoretical KV-cache allocation: $\sim 83.88$ MB
   - Framework & activation buffers: $\sim 60 - 90$ MB
   - Expected Total Resident RAM: **$\sim 350 - 450$ MB**.
5. Confirm system does **NOT** trigger memory pressure warnings or OS jetam kill (iOS limits foreground app to $\sim 2.5 - 3.0$ GB on iPhone 13 Pro).

---

## SECTION K: TIME-TO-FIRST-TOKEN (TTFT) MEASUREMENT

1. Use Instruments or in-app diagnostic timer logging:
   - Start: User taps send / STT finalizes prompt.
   - Stop: First token emitted by `SmolLM2Sampler` and yielded to UI continuation.
2. Target on Apple A15 Bionic (Neural Engine + GPU):
   - Short prompt ($<30$ tokens): **$80\text{ ms} - 250\text{ ms}$**.
   - Long prompt ($200+$ tokens): **$200\text{ ms} - 600\text{ ms}$**.

---

## SECTION L: TOKENS PER SECOND (DECODE SPEED) MEASUREMENT

1. In Xcode console or Capabilities diagnostic:
   - Formula: $\text{Tokens/sec} = \frac{\text{Total Generated Tokens} - 1}{\text{Timestamp of Last Token} - \text{Timestamp of First Token}}$
2. Target on Apple A15 Bionic:
   - Expected Decode Speed: **$25 - 45\text{ tokens/sec}$**.

---

## SECTION M: THERMAL BEHAVIOR TEST

1. Run 5 consecutive 100-token generations.
2. Query `ProcessInfo.processInfo.thermalState`:
   - `.nominal` (Standard operation, zero throttling)
   - `.fair` (Slight warmth, no perceptible throttling)
   - `.serious` (Thermal limit approached, frequency reduced)
   - `.critical` (Severe throttling)
3. Ensure iPhone stays in `.nominal` or `.fair` across ordinary usage.

---

## SECTION N: FAILURE RECOVERY & EDGE CASE TEST

1. **Missing Weights Test**:
   - Temporarily rename `SmolLM2-360M-Instruct-4bit.mlmodelc` to `.bak`.
   - Open NOVA and send a message.
   - Verify UI displays: `Notice: SmolLM2-360M-Instruct weights not found on disk...`.
   - Verify zero crash, zero fake responses, and zero fallback to remote APIs.
2. **Context Overflow Test (Boundary + 1)**:
   - Send a prompt exceeding 2048 tokens.
   - Verify provider catches the boundary error immediately and notifies user cleanly.

---

## PHASE 7 DEVICE REPORT TEMPLATE

```text
================================================================================
PHASE 7 PHYSICAL DEVICE VERIFICATION REPORT
================================================================================

Device:               iPhone 13 Pro (Model A2638 / 6 GB RAM)
OS:                   iOS 18.x (Build: __________)
Model:                SmolLM2-360M-Instruct-4bit.mlmodelc
Provider:             SmolLM2Provider (coreml.smollm2.360m)
Model Load Time:      ______ ms
First Token (TTFT):   ______ ms
Decode Speed:         ______ tokens/sec
Peak Resident RAM:    ______ MB
Thermal State:        Nominal / Fair / Serious
Cancellation:         PASS / FAIL (Immediate abort verified)
Streaming:            PASS / FAIL (Sequential delivery verified)
Long Context (2048):  PASS / FAIL (Boundary respected)
Recovery:             PASS / FAIL (Graceful missing weights handling)

TEST PROMPT RESULTS:
1. "Hello, who are you?":
   Output: ____________________________________________________________________
   Quality: Coherent / Incoherent

2. "Explain what memory means in one sentence.":
   Output: ____________________________________________________________________
   Quality: Concise / Verbose

3. "Count from 1 to 50.":
   Output: ____________________________________________________________________
   Quality: Complete / Truncated

4. "Write a short paragraph about the ocean.":
   Output: ____________________________________________________________________
   Quality: Natural / Degraded

FINAL VERDICT:
[ ] APPROVED FOR PRODUCTION DEPLOYMENT
[ ] REQUIRES TUNING (Specify: ________________________________________)
================================================================================
```
