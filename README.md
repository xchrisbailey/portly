# Portly

A macOS menu bar app that shows which local dev servers are listening on which ports, and lets you kill them.

Ever hit `EADDRINUSE`, or wondered which forgotten Vite process is still holding port 3000? Click the Portly icon, see everything that's running, and end it with one click.

## Install

1. Download the latest `Portly-X.Y.Z.dmg` from the [Releases page](https://github.com/xchrisbailey/portly/releases/latest).
2. Open the DMG and drag Portly into `/Applications`.
3. Launch it. Portly lives in the menu bar and has no Dock icon.

Requires macOS 14 (Sonoma) or later. The app is signed and notarized.

To start Portly automatically, open its menu and tick **Launch at login**.

## Using Portly

Click the menu bar icon to see a list of your running dev servers. Each row shows the port, the project name, and the command that started it, for example `3000, 24678 · web · vite`.

| Action | How |
| --- | --- |
| Open the server in your browser | Click the row |
| Kill the server | Click the **✕** on the row |
| Copy the URL or PID | Right-click the row |
| Open the project folder | Right-click the row, **Reveal in Finder** |
| See the full command and PID | Hover over the row |
| See non-JavaScript listeners too | Tick **Show all listeners** |

The list refreshes each time you open the menu.

### What counts as a dev server

By default Portly shows processes running under **node**, **bun**, or **deno** that are listening for TCP connections. The project name comes from the nearest `package.json` (or the folder name if there isn't one).

**Show all listeners** widens the list to anything listening on a port you can reach from localhost: Postgres, Docker, other apps. Those rows work like the rest, except as noted below.

### The Exposed badge

An orange **Exposed** badge means the server is bound to all network interfaces, not just localhost, so other machines on your network can reach it. If you didn't mean that, restart it bound to `127.0.0.1`.

### What Kill does

Killing the one process that holds the port rarely works. Tools like nodemon and `next dev` respawn it within a second, and wrappers like `npm run` stick around. So Portly ends the server together with every process launched by the same command, asking nicely first (SIGTERM) and forcing it (SIGKILL) if it doesn't exit promptly. Your terminal shell is left alone.

- **Siblings:** if one command runs several servers (`turbo dev`, `concurrently`), killing one kills them all. The row warns you first, for example `also kills :4000, :5000`.
- **Other listeners:** non-dev-server processes (shown with **Show all listeners**) are killed by PID only.
- **Can't kill:** macOS system processes are protected, and processes owned by another user show an error instead of being killed.

The reasoning is in [ADR 0001](docs/adr/0001-kill-targets-process-group.md).

## Command line

The same binary has a headless mode, handy for scripting or checking what Portly sees:

```sh
Portly --scan          # dev servers as JSON
Portly --scan --all    # all listeners as JSON
Portly --kill <pid>    # kill that row and print the outcome
```

Inside the app bundle the binary is at `/Applications/Portly.app/Contents/MacOS/Portly`.

## Build from source

You need Xcode (or the Swift 6 toolchain) on macOS 14 or later.

```sh
swift build           # build
swift test            # run the tests
scripts/build-app.sh --build-only   # build Portly.app without installing it
```

## Contributing

- Issues are tracked on [GitHub](https://github.com/xchrisbailey/portly/issues).
- `scripts/check.sh commit` and `scripts/check.sh push` run before every commit and push. `scripts/setup-hooks.sh` wires them up in a fresh clone.
- Domain terms (Listener, Dev Server, Kill, Sibling, …) are defined in [GLOSSARY.md](GLOSSARY.md). Coding conventions are in [CODING_STANDARDS.md](CODING_STANDARDS.md).
- Maintainers cut releases with `scripts/release.sh`; see [docs/agents/release.md](docs/agents/release.md).

## Website

The GitHub Pages landing page lives in `site/`, with no build step or dependencies. Preview it with `python3 -m http.server 8000 --directory site`.

To publish, set **Settings → Pages → Source** to **GitHub Actions**, then push to `main` or manually run **Deploy landing page**. The site will be at https://xchrisbailey.github.io/portly/. The download button resolves the latest release’s DMG, falling back to the releases page if GitHub’s API is unavailable.

Public downloads require a public repository: GitHub does not expose private release assets to anonymous visitors. If the repository stays private, host the downloads publicly elsewhere and update the download link before publishing.
