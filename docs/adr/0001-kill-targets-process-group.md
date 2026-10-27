# Kill targets the Dev Server's process group

Killing only the process that holds the port doesn't stick: watchers like nodemon, `tsx watch`, and `next dev` respawn the child within a second, and wrappers like `npm run` are left behind. So Kill sends its signals to the Dev Server's whole process group, which covers the wrappers and watchers launched by the same command but not the terminal shell. The cost is that tools running several servers under one command (`turbo dev`, `concurrently`) put them in one group, so killing one kills its Siblings. The row warns when that will happen ("also kills :4000") rather than hiding it.

## Consequences

- Listeners that aren't Dev Servers (postgres, Docker, GUI apps) are killed by PID only, never by group, and macOS system binaries can't be killed at all.
