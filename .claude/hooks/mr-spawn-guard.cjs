#!/usr/bin/env node
// t1k-origin: kit=theonekit-model-router | repo=The1Studio/theonekit-model-router | module=null | protected=false
// mr-spawn-guard.cjs — P0 safety hook
// Prevents delegated sessions from re-entering model-router delegation.
// Registered as PreToolUse hook matching "Bash" in spawned sessions.
//
// When MR_SPAWNED=1 (set by mr-delegate.sh), this hook blocks any
// Bash command that invokes mr-delegate.sh, preventing recursive delegation.

const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));

// Only check Bash tool calls
if (input.tool_name !== 'Bash') {
  process.exit(0);
}

const command = input.tool_input?.command || '';

// Block recursive delegation
if (command.includes('mr-delegate') || command.includes('model-router')) {
  process.stderr.write('Blocked: recursive delegation not allowed in spawned session\n');
  process.exit(2); // exit 2 = block operation
}

process.exit(0);
