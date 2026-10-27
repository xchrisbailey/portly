# Coding standards

Read during review. Formatting and layout are enforced by `swift format lint` (config in `.swift-format`), so this file holds only judgement calls.

## Core vs app

- **PortlyCore exposes data; the app writes words.** User-facing strings (row subtitles, warnings, error text) live in the app target. A core type returning display text is a violation.
- **The OS is reached only through the injected boundaries** (`ProcessSource`, `FileLookup`, `Signaller`). Core code calling `lsof`, `kill`, `proc_*`, or the filesystem directly is a violation. Real adapters live in the app target.
- **Each policy lives in one place.** Kill targeting and the system-binary rule belong in `Kill.swift`; Project naming in `Project.swift`. A second copy of a rule elsewhere, even a partial one, is a violation.

## Tests

- **Tests go through the public Scan and Kill seam with fakes.** A test reaching into a private helper, or asserting on parser internals, is a violation.
- **A behaviour that only the real adapters exhibit** (signal semantics, `lsof` field parsing) gets covered by `scripts/smoke.sh` or a fixture captured from real output, not by a fake that assumes the answer.

## Language

- **Names use `GLOSSARY.md` terms** (Listener, Dev Server, Runtime, Project, Exposed, Kill, Sibling) and avoid the terms it lists under _Avoid_.
- **A change that contradicts an ADR in `docs/adr/` says so** in the commit message or PR, rather than silently overriding it.
