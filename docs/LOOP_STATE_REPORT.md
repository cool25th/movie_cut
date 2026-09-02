# LOOP STATE REPORT (generated — do not hand-edit)

_Generated: 2026-09-02T10:07:03 from `.build-check/history/` (last 3 runs per gate)._
## verify_gate (5-step)
| run | steps | overall |
|---|---|---|
| 09-02 07:43 | swift build:OK xcodebuild:OK lint gate:OK swift test:OK | GATE_PASS |
| 09-02 08:22 | swift build:OK xcodebuild:OK swift test:FAIL | GATE_FAIL |
| 09-02 08:26 | swift build:OK xcodebuild:OK lint gate:OK swift test:OK | GATE_PASS |

## W smoke (representative workflows)
| run | workflows | steps | verdict |
|---|---|---|---|
| 08-31 14:09 | 5/5 | 29/29 | PASS |

## Core editing parity (preview ↔ export)
| run | scenarios | failing | worst MAD |
|---|---|---|---|
| 08-31 15:22 | 15/19 | cross_dissolve, normal_delete, freeze_frame, motion_tracking | — |
| 09-02 10:06 | 1/1 | — | 3.36 |

_Known registered flakes appear here by name until their root (BUG-CA12-01 class) is fixed — the table shows what WAS measured, not what we wish were true._
