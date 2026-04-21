#!/usr/bin/env node
/**
 * mr-update-check.cjs — SessionStart hook
 * Checks for CCS and oc-go-cc updates periodically (max once per 24h).
 * Non-blocking: writes update notice to stderr, never fails the session.
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const STATE_DIR = path.join(process.env.HOME || '/tmp', '.model-router');
const CHECK_FILE = path.join(STATE_DIR, 'last-update-check.json');
const CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000; // 24 hours

try {
  // Skip in spawned sessions
  if (process.env.MR_SPAWNED === '1') {
    process.exit(0);
  }

  // Check if we should run (throttle to once per 24h)
  let lastCheck = 0;
  try {
    const state = JSON.parse(fs.readFileSync(CHECK_FILE, 'utf8'));
    lastCheck = state.ts || 0;
  } catch { /* first run */ }

  if (Date.now() - lastCheck < CHECK_INTERVAL_MS) {
    process.exit(0);
  }

  // Save check timestamp first (prevent concurrent checks)
  fs.mkdirSync(STATE_DIR, { recursive: true });
  fs.writeFileSync(CHECK_FILE, JSON.stringify({ ts: Date.now() }));

  const updates = [];

  // Check CCS
  try {
    const installed = execSync('ccs --version 2>/dev/null', { encoding: 'utf8', timeout: 5000 }).trim().split('\n')[0];
    const latest = execSync('npm view @kaitranntt/ccs version 2>/dev/null', { encoding: 'utf8', timeout: 10000 }).trim();
    const installedVer = installed.match(/v?([\d.]+)/)?.[1];
    if (installedVer && latest && installedVer !== latest) {
      updates.push(`CCS: ${installedVer} → ${latest} (npm update -g @kaitranntt/ccs)`);
    }
  } catch { /* skip */ }

  // Check oc-go-cc
  try {
    const installed = execSync('oc-go-cc --version 2>/dev/null || /tmp/oc-go-cc --version 2>/dev/null', { encoding: 'utf8', timeout: 5000 }).trim();
    const installedVer = installed.match(/v?([\d.]+)/)?.[1];
    const latestTag = execSync('curl -fsSL -o /dev/null -w "%{redirect_url}" https://github.com/The1Studio/oc-go-cc/releases/latest 2>/dev/null', { encoding: 'utf8', timeout: 10000 }).trim();
    const latestVer = latestTag.match(/v?([\d.]+)/)?.[1];
    if (installedVer && latestVer && installedVer !== latestVer) {
      updates.push(`oc-go-cc: ${installedVer} → ${latestVer} (download from GitHub releases)`);
    }
  } catch { /* skip */ }

  if (updates.length > 0) {
    process.stderr.write('\n[model-router] Updates available:\n');
    for (const u of updates) {
      process.stderr.write(`  ${u}\n`);
    }
    process.stderr.write('\n');
  }
} catch {
  // Never fail the session
}

process.exit(0);
