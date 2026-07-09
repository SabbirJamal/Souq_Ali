# Bizsooq OTP Autofill Handoff

This file is for the next Codex chat. Continue from here without scanning the whole repo unless the user explicitly asks.

## Project

- Flutter/Firebase app path: `D:\souqaliv1`
- Follow `AGENTS.md` strictly:
  - Do not analyze the full repository unless explicitly requested.
  - Only inspect files directly related to the current task.
  - Prefer minimal diffs.
  - Avoid unnecessary package additions.
  - Keep responses concise.

## Current Task

Implement SMS OTP auto-fill for the existing Twilio Verify login flow.

Desired flow:

1. User enters Oman phone number on login page.
2. User clicks `Get OTP`.
3. OTP popup opens.
4. SMS arrives.
5. OTP automatically fills into the popup boxes.
6. User manually clicks `LOGIN`.

Do not auto-submit after OTP autofills.

## Current Login UI State

The app already has OTP UI working manually:

- Phone number input.
- Terms checkbox selected by default.
- Button text: `Get OTP`.
- After requesting OTP, popup appears with:
  - Heading: `Enter OTP`
  - Text: `Code sent to +968 ...`
  - 5 OTP boxes
  - Resend timer / `Request Again`
  - Orange `LOGIN` button
  - Top-right close icon

Manual OTP entry and login are working.

## Backend State

Firebase Functions already exist:

- `sendOtp`
- `verifyOtp`

Twilio Verify is already upgraded and working. OTP SMS is successfully sent now.

Deploy command used:

```powershell
firebase.cmd deploy --only functions:sendOtp,functions:verifyOtp --project souqali-42fd9
```

## Twilio State

- Twilio account is upgraded from trial.
- Verify service exists and works.
- User tried custom templates, but the practical path chosen is app-side autofill using SMS Retriever/App Hash.
- No extra Twilio cost is expected for autofill itself. SMS cost remains normal Twilio OTP SMS cost.

## Important Technical Direction

Use Android SMS Retriever style autofill.

Likely package:

```yaml
sms_autofill
```

Implementation idea:

1. Add `sms_autofill` if not already present.
2. In Flutter login page:
   - Get app signature/hash:
     ```dart
     final appHash = await SmsAutoFill().getAppSignature;
     ```
   - Send `appHash` to `sendOtp`.
3. In Firebase `sendOtp`:
   - Accept optional `appHash`.
   - Pass it to Twilio Verify as `AppHash` / `appHash` depending on current Twilio SDK syntax in `functions/index.js`.
4. In OTP popup:
   - Use `CodeAutoFill`.
   - Call `listenForCode()` when popup opens.
   - Call `cancel()` on dispose/close.
   - Implement `codeUpdated()` to fill the 5 OTP controllers.
   - Do not auto-login.
5. Add `AutofillHints.oneTimeCode` to OTP inputs as fallback.

## Files Likely Involved

Only inspect these first:

- `lib/seller_login_page.dart`
- `functions/index.js`
- `pubspec.yaml`

Do not repo-wide search unless needed.

## Expected SMS Format

For Android SMS Retriever to autofill silently, the SMS generally needs the app hash at the end. Example shape:

```text
Your Bizsooq verification code is: 12345

AbCdEfGhIjK
```

Twilio Verify may add this when `appHash` is provided. Verify exact current SDK parameter from the existing function code or package docs if needed.

## Validation Steps

After changes:

1. Run:
   ```powershell
   flutter pub get
   ```
   only if dependency changed.
2. Format edited Dart:
   ```powershell
   dart format lib\seller_login_page.dart
   ```
3. Deploy functions if `functions/index.js` changes:
   ```powershell
   firebase.cmd deploy --only functions:sendOtp --project souqali-42fd9
   ```
4. Rebuild/reinstall app on Android device.
5. Test:
   - Enter phone number.
   - Tap `Get OTP`.
   - Keep OTP popup open.
   - Confirm SMS arrives.
   - Confirm OTP boxes fill automatically.
   - Confirm user still taps `LOGIN`.

## Notes

- Firebase App Check warning in console was seen before:
  `No AppCheckProvider installed`
  This was not the reason OTP failed earlier.
- OTP started working after Twilio account upgrade.
- Keep UI unchanged except for enabling autofill behavior.
- Avoid broad cleanup or unrelated fixes.
