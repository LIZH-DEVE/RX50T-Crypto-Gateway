# Day 08

## Goal

Upgrade the `RX50T` BRAM-backed ACL path from GUI-side session counting to true board-side per-rule hardware counters, then expose those counters through the UART protocol and GUI.

## Completed

- added a new board-side rule-counter query command:
  - request: `55 01 48`
  - response: `48 x y z w p r t u 0A`
- added `8` hardware ACL counters in the top-level probe path for the shipped default rules:
  - `X / Y / Z / W / P / R / T / U`
- preserved the existing aggregate stats command:
  - `55 01 3F -> 53 total acl aes sm4 err 0A`
- extended the Python protocol layer with:
  - `AclRuleCounters`
  - `parse_rule_stats_response(...)`
  - `case_query_rule_stats(...)`
- extended the CLI tool with:
  - `--query-rule-stats`
  - `--expect-rule-stats`
- updated the GUI so it now:
  - queries board-side rule counters
  - highlights non-zero hardware counters
  - shows a board-side `Hot Rule`
  - auto-refreshes rule counters shortly after an ACL block event

## Verification

### Python / host-side

- `py -3 -m unittest D:\FPGAhanjia\jichuangsai\contest_project\tools\test_crypto_gateway_protocol.py`
  - passed (`10` tests)
- `py -3 -m py_compile ...`
  - passed
- GUI import check:
  - passed

### RTL / implementation

- fresh Vivado build:
  - passed
- latest implementation results:
  - `WNS = 6.104ns`
  - `WHS = 0.094ns`
  - `DRC = 0`
  - `Slice LUTs = 4445`
  - `Slice Registers = 5048`
  - `Slice = 1856`
  - `RAMB18 = 1`

### Real-board smoke

In a persistent single serial session:

- before:
  - `X=1, P=0`
- `XYZ -> 44 0A`
- `PQR -> 44 0A`
- after:
  - `X=2, P=1`
- observed rule-counter delta:
  - `X:+1`
  - `P:+1`

## Notes

- the board-side counters are now the authoritative source for rule hits
- the GUI no longer depends on session-local synthetic rule counting for the hot-rule display
- immediate back-to-back host queries right after a block can observe stale values, so the GUI now inserts a short delayed hardware refresh after ACL block events

## Next Step

- if we want deeper observability, the next logical upgrade is runtime ACL rule updates or per-rule persistent export from the GUI
