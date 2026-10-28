# DMG prototype (wayfinder #13)

Throwaway. Plain `hdiutil` + Finder AppleScript; background drawn with python3/PIL.

    scripts: make-dmg.sh <path/to/Portly.app> <version> [outdir]

Verdict: window layout approved (660x400, icon size 128, app at 170,200, Applications at 490,200, arrow background). Use plain hdiutil for now. Known risks: `hdiutil create/attach/convert` print deprecation warnings (diskutil image replacements exist); the layout step needs Finder Automation permission and is not headless-safe.
