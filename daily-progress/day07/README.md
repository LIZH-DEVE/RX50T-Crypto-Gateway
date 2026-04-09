# Day 07

## Goal

Make the GUI more useful for demonstrations by showing not only the compiled ACL rule table, but also which rules are actually hot during the current session.

## Completed

- added a shared protocol helper to extract the first payload key from a transmitted frame
- added protocol unit tests for first-key extraction
- extended the Tkinter GUI with:
  - per-rule ACL hit counters
  - highlighted counters for rules that have fired
  - a `Hot Rule` summary banner in the ACL panel
- kept the board-side UART protocol unchanged
- kept the feature entirely on the GUI side, so no RTL or bitstream changes were required for this step

## Verification

- `test_crypto_gateway_protocol.py`: pass
- `py_compile` for GUI and protocol modules: pass
- GUI import check: pass

## Boundary

- the displayed per-rule hit counts are session-local GUI counters
- they are derived from GUI-observed `D\\n` ACL block responses
- they are not yet persistent across sessions
- they are not yet true board-side per-rule hardware counters

## Next Step

- either add board-side per-rule hardware counters
- or add a small GUI reset/export action for ACL session telemetry
