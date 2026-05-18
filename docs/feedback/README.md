# Demo Feedback Log

One file per demo session. Filename pattern:

```
YYYY-MM-DD_session-<n>.md
```

Each file captures:

1. **Attendees** (role + name)
2. **Build** (git short SHA, Vercel preview URL or local commit)
3. **Scope walked through** — which screens, which flows
4. **Verbatim feedback** — bullet list, no paraphrasing
5. **Decisions taken in the room** — what changed in scope/UI
6. **Open items** — fed back into `CLAUDE.md` §16 if architectural,
   into the screen-inventory backlog if UI

A template is in `_template.md`. Copy it for each session.

## Why a folder, not a tracker

The PDD demo cycle is short (weeks, not months) and verbatim feedback
gets paraphrased into trackers and loses nuance. Markdown in git keeps
the original wording and the diff history.
