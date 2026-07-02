# Listen Server Lifecycle Plan

> Follow-up plan for the accepted real listen-server scope.

## Goal

Clean up the lifecycle and process-management edges of the hosted local server path in `client/scripts/network_manager.gd` and `server/network_manager.gd`.

## Scope

- Replace the fixed `0.5s` host-start delay with readiness detection.
- Clean up stale `hosted_server_pid` values when the server exits.
- Handle local port conflicts more explicitly.
- Shut down the hosted process when the host disconnects or exits.
- Confirm host peer authority and role behavior remains correct.
- Add manual and automated smoke tests for host/join/start/exit flows.

## Notes

- This plan intentionally stays separate from the current review-fix batch.
- It does not change gameplay mechanics.
