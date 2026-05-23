# AGENTS.md

## Global Rules

- Never analyze the full repository unless explicitly requested.
- Only inspect files directly related to the task.
- Ask for missing files instead of performing broad searches.
- Keep responses concise and implementation-focused.
- Prefer minimal diffs over full rewrites.
- Avoid unnecessary explanations.
- Never reread unchanged files unnecessarily.
- Do not perform repo-wide searches unless explicitly requested.
- Ignore build, generated, cache, and dependency folders.
- Avoid duplicate code generation.
- Do not retry failed approaches automatically.
- Break large tasks into smaller steps.
- Prioritize low token and low compute usage at all times.
- Use targeted edits only.
- Assume existing architecture is intentional unless told otherwise.

## Additional Guidance

- Keep outputs minimal unless detailed explanation is requested.
- Avoid unnecessary formatting and verbose responses.
- Focus on solving only the requested issue.
- Reuse existing project patterns whenever possible.
- Avoid unnecessary package or dependency additions.

Follow AGENTS.md strictly for all future tasks in this repository.
