# SouqAli / BIZSOOQ - CLAUDE.md

## Main Goal

Improve app performance, smoothness, loading speed, memory usage, and responsiveness.

Critical rule:

- Do NOT change the current UI.
- Do NOT change current features.
- Do NOT change how the app behaves.
- Do NOT change Firebase/Auth/Firestore/Storage logic.
- Do NOT change database schema, collections, fields, rules, indexes, queries, uploads, downloads, or authentication flow.

Claude may inspect Firebase-related files only to understand performance issues, but must NOT edit them.

If a performance issue is related to Firebase, Firestore, Firebase Storage, database reads, uploads, downloads, queries, pagination, or caching, only give suggestions/ideas. Do not modify that code.

Firebase/database-related implementation will be handled separately by Codex.

---

## Startup Rules

Read this file first at the start of every session.

Before making any changes:

1. Understand the relevant code.
2. Identify root cause.
3. Decide whether the fix is app-side or Firebase/database-side.
4. If app-side, make the smallest safe change.
5. If Firebase/database-side, only report the idea. Do not edit.
6. Preserve existing functionality.

---

## Response Style

Use caveman mode.

- No greetings.
- No praise.
- No long summaries.
- No unnecessary explanations.
- Be concise.
- Show changed files only.
- Stop when task is complete.

---

## Project Rules

- Preserve existing UI unless explicitly requested.
- Preserve existing features.
- Preserve current app behavior.
- Do not rename files unless necessary.
- Do not refactor unrelated code.
- Do not introduce breaking changes.
- Follow existing project architecture and patterns.

---

## Strict Firebase / Backend Protection Rules

Do NOT edit:

- Firebase Auth logic
- Firestore queries
- Firestore collection names
- Firestore field names
- Firestore data models
- Firebase Storage upload logic
- Firebase Storage download logic
- Firebase Security Rules
- Firebase indexes
- Firebase initialization/configuration
- OTP/phone authentication flow
- Backend/database business logic

Allowed:

- Read Firebase-related files for understanding only.
- Report Firebase/database performance ideas separately.
- Suggest improvements without applying them.

When Firebase/database performance issue is found, use this format:

Firebase Idea:
Reason:
Expected Benefit:
Files to review with Codex:

Do not implement it.

---

## Allowed Performance Work

Claude MAY optimize app-side Flutter performance only.

Allowed areas:

- Widget rebuild reduction
- const constructors
- controller disposal
- stream subscription cleanup
- memory leak fixes
- unnecessary setState reduction
- list/grid rendering improvements
- image widget rendering improvements without changing Firebase logic
- video player lifecycle improvements
- camera controller lifecycle improvements
- async loading state cleanup
- navigation performance
- startup performance
- animation smoothness
- scroll performance
- duplicate computation reduction
- heavy work moved away from build methods

---

## Not Allowed

Do NOT:

- Change UI layout
- Change colors
- Change spacing
- Change fonts
- Change screen design
- Change feature behavior
- Remove features
- Rewrite full screens
- Rewrite Firebase services
- Change Firestore/Storage fetch logic
- Change authentication
- Change database schema
- Add risky packages without approval

---

## Flutter Rules

- Maintain existing navigation.
- Maintain existing user flows.
- Maintain Firebase compatibility.
- Maintain Firestore compatibility.
- Maintain Firebase Storage compatibility.
- Keep changes minimal and safe.
- Prefer localized fixes over big refactors.

---

## Performance Audit Rules

When asked to optimize performance:

1. Scan the project.
2. Separate issues into:
   - App-side Flutter issues
   - Firebase/database-related issues
3. Implement only app-side Flutter improvements.
4. For Firebase/database issues, give ideas only.
5. Do not touch Firebase/database files unless explicitly approved.

Rank findings:

- Critical
- High
- Medium
- Low

Focus first on Critical and High.

---

## Debugging Output Format

Use this format:

Problem:
Root Cause:
Fix:
Changed Files:
Firebase Ideas:

Keep it short unless more detail is requested.

---

## Code Change Rules

Before editing:

- Inspect related files.
- Check dependencies.
- Check side effects.
- Verify whether the fix touches Firebase/database logic.
- If it touches Firebase/database logic, stop and report suggestion only.

After editing:

- Verify no existing feature is broken.
- Verify UI remains unchanged.
- Verify behavior remains unchanged.
- Report only relevant changes.

---

## Token Saving Rules

- Minimize output tokens.
- Do not repeat information.
- Do not explain obvious code.
- Return only actionable information.
- Prefer direct answers.
- Avoid long reports unless requested.

---

## Best Prompt To Use In Claude Code

Read CLAUDE.md first.

Analyze the entire Flutter project for performance problems.

Goal:
Make the app faster, smoother, and more optimized.

Rules:
- Do not change UI.
- Do not change features.
- Do not change app behavior.
- Do not edit Firebase/Auth/Firestore/Storage/database logic.
- If performance issue is database/Firebase-related, only give me ideas for Codex.
- Implement only safe app-side Flutter performance improvements.

Focus on:
- widget rebuilds
- memory leaks
- controller disposal
- list/grid performance
- image/video widget performance
- camera lifecycle
- async loading
- startup speed
- scroll smoothness
- unnecessary computations

Output:
Problem:
Root Cause:
Fix:
Changed Files:
Firebase Ideas:

Start with audit first. Do not modify anything until I say implement.
