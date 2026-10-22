# Phase 7 render acceptance (Task 61)

Scope: Direction C after Tasks 57–60. No app packaging or launch.
References: `docs/design/directions.html` section C and `docs/design/direction-C.png`.

## Coverage and TDD

The initial coverage test failed: the previous matrix had six sections and omitted
Settings. The Phase 7 matrix now covers seven: full Me, Picks and Training popovers
(440×720 pt), a dimension detail, village Training detail, Settings (440×600 pt),
and the actual ProSheet (440×660 pt), including its Done button.

Both the synthetic fixture and real engine snapshots run in zh/en and light/dark.
OCR checks page content as well as the header/tab bar, trial and activation actions.
Optional sections are asserted when their snapshot data exists. A Sources scan
rejects the four retired Bauhaus hex values, case-insensitively, in #/0x notation.

The full-suite run exposed older render tests checking English-only or retired
uppercase headings. Those assertions now check the current localized headings.
The older full-height list OCR checks use a smaller minimum text height to include
caption-sized content; none of their privacy or copy exclusions were removed.

## Reproduce offline

From the worktree root, generate private local snapshots with the checkout engine:

```sh
.venv/bin/python - <<'PYTHON'
import pathlib, subprocess, sys
root = pathlib.Path('.pytest_cache/phase7')
root.mkdir(parents=True, exist_ok=True)
for locale in ('zh', 'en'):
    with (root / (locale + '.json')).open('wb') as output:
        subprocess.run([sys.executable, '-m', 'agentfit.engine', 'snapshot', '--json',
                        '--locale', locale, '--state-dir', str(root / 'state')],
                       stdout=output, check=True)
PYTHON
.venv/bin/python -m pytest -q --basetemp=.pytest_cache/tmp
cd macos
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
PHASE7_SNAPSHOT_DIR="$PWD/../.pytest_cache/phase7" \
PHASE7_RENDER_OUT="$PWD/../.pytest_cache/phase7/render" \
swift test --disable-sandbox
```

SwiftPM's nested sandbox cannot run in the execution sandbox, and Vision OCR
requires access to macOS system services. The test run used an approved execution
outside that sandbox; module caches and render outputs point into the worktree.
Without the two PHASE7 variables, real-data acceptance is explicitly skipped;
the synthetic matrix and source-color guard still run.

Snapshots, isolated engine state, 28 real-data PNGs and execution logs remain in
ignored `.pytest_cache/`. No private snapshots or rendered user data are committed.
PNG names: `render-{zh,en}-{section}-{light,dark}.png`.

## Visual inspection and limits

Inspected real-data renders show Direction C's neutral surfaces, teal score rings,
progress and primary actions, segmented tabs, rounded cards and adaptive dark
palette. Settings and the full Pro sheet share the same theme. The reference's
sample numbers and rankings are not substituted for real data.

This is render verification, not pixel-identical approval: the existing popover
keeps its update/Settings footer. At the initial scroll position the Me usage line
and the bottom of Training content reach the scroll viewport edge; longer Picks
lists and Settings content continue below the fold. These are recorded differences
from the static reference, not corrected by this test-only task. Native vibrancy
over a desktop, scrolling, keyboard/VoiceOver behavior and app interaction were
not verified, because the app was not launched.

## Final validation

- `.venv/bin/python -m pytest -q --basetemp=.pytest_cache/tmp`: 697 passed,
  3 skipped. Neither of the two historical analytics failures reproduced here.
- Full `swift test --disable-sandbox` with the environment above: 204 tests,
  14 skipped, 0 failures. The Phase 7 real-data render test ran and passed;
  skips belong to other optional acceptance tests.
- `git diff --check`: clean.
