# Portly

A macOS menu bar utility that shows which local development servers are listening on which ports, and lets you kill them.

## Language

**Listener**:
Any process with a TCP socket in the listening state that is reachable from localhost, whether bound to loopback or to all interfaces.
_Avoid_: Port process, service

**Dev Server**:
A Listener whose Runtime is node, bun, or deno. The default subject of everything Portly shows.
_Avoid_: Node process, app, server

**Runtime**:
The JavaScript engine executable a Dev Server runs under: node, bun, or deno.
_Avoid_: Engine, interpreter

**Project**:
The codebase a Dev Server was started from, named by the nearest enclosing `package.json` (without its scope) or, failing that, its folder name.
_Avoid_: App, repo, workspace

**Exposed**:
A Listener bound to all interfaces rather than loopback only, so it is reachable from other machines on the network.
_Avoid_: Public, external

**Kill**:
Ending a Dev Server together with every process launched by the same command (its wrappers and watchers), gracefully first and forcibly if it does not exit promptly. A Listener that isn't a Dev Server is killed alone, by PID only, in the same two steps.
_Avoid_: Stop, terminate, close

**Sibling**:
Another Dev Server launched by the same command as the one being killed, which therefore dies with it.
_Avoid_: Related server, child
