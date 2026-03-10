# BlueDriver OBD Integration Experiments

This note tracks how we validate and integrate the **BlueDriver Bluetooth Pro OBD2** adapter with Inclinati.

Goal: stream reliable vehicle telemetry (RPM, speed, coolant temp, throttle, DTCs) and correlate it with inclinometer data.

## Why This Direction

BlueDriver is a stronger fit for field testing because it is stable, user-friendly, and widely used by both DIY and professional users. For us, that means less pairing friction and better confidence in live diagnostics.

## Current App Status

Inclinati already includes a generic BLE probe screen:

- File: `lib/obd/probe_screen.dart`
- Entry point: OBD button on the main dashboard
- Features:
  - BLE scan + connect
  - GATT service/characteristic discovery
  - Auto-pick TX/RX characteristics
  - Notification stream logging (ASCII + HEX)
  - Manual OBD command send (ELM-style, `\r` terminated)
  - BlueDriver-focused helpers:
    - "BlueDriver only" scan filter
    - `INIT` sequence (`ATZ`, `ATE0`, `ATL0`, `ATS0`, `ATH0`, `ATSP0`)
    - Quick PID buttons (`010C`, `010D`, `0105`, `0111`, `03`, `04`)

## Test Procedure (Phone + Vehicle)

1. Plug BlueDriver into OBD-II port and turn ignition to ACC/ON.
2. Open Inclinati → `OBD`.
3. Tap scan.
4. If needed, disable **BlueDriver only** to show all BLE adapters.
5. Connect to the strongest likely BlueDriver candidate.
6. After connect, press `INIT` once.
7. Send/verify core commands:
   - `010C` (RPM)
   - `010D` (speed)
   - `0105` (coolant temp)
   - `0111` (throttle position)
8. Confirm activity log receives readable responses and/or hex payloads.

## Response Validation

Use these checks during capture sessions:

- RPM (`010C`) should track throttle changes quickly.
- Speed (`010D`) should correlate with GPS speed trend (not necessarily exact instant values).
- Coolant (`0105`) should be plausible and stable once engine is warm.
- DTC query (`03`) should return no-code format on healthy vehicles.

## Known Reality

Even with ELM-style commands, BLE OBD adapters may differ in transport details:

- Different GATT layouts (TX/RX characteristics)
- Write-with-response vs write-without-response behavior
- Fragmented notifications (multi-packet responses)

The current probe intentionally logs raw data so we can confirm behavior before hardcoding adapter-specific assumptions.

## Next Integration Steps

1. Persist last successful BlueDriver device ID for faster reconnect.
2. Add parser layer to decode PID responses into typed telemetry fields.
3. Feed parsed OBD speed/RPM into `InclinometerData` alongside GPS/sensor metrics.
4. Add a compact OBD status strip on the dashboard (connected, RPM, coolant, DTC count).
5. Record short drive traces (OBD + inclinometer) for consistency checks.

## iOS Permission Copy

Bluetooth permission text now references BlueDriver/compatible OBD BLE adapters in `ios/Runner/Info.plist`.

