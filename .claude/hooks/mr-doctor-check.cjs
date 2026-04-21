#!/usr/bin/env node
/**
 * mr-doctor-check.cjs — Doctor hook for model-router
 * Registered as a doctor check that t1k doctor discovers.
 * Validates: CCS, oc-go-cc, API key, CCS profile, proxy health, agents, skill.
 *
 * Exit codes:
 *   0 = all checks pass
 *   1 = one or more checks failed (doctor reports issues)
 *
 * Output: JSON array of check results to stdout
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const results = [];
let hasFailure = false;

function check(name, fn) {
  try {
    const result = fn();
    results.push({ name, status: result.status, message: result.message });
    if (result.status === 'fail') hasFailure = true;
  } catch (err) {
    results.push({ name, status: 'fail', message: err.message });
    hasFailure = true;
  }
}

// 1. CCS installed
check('ccs-installed', () => {
  try {
    const ver = execSync('ccs --version 2>/dev/null', { encoding: 'utf8', timeout: 5000 }).trim().split('\n')[0];
    return { status: 'pass', message: ver };
  } catch {
    return { status: 'fail', message: 'CCS not found. Install: npm install -g @kaitranntt/ccs' };
  }
});

// 2. oc-go-cc installed
check('oc-go-cc-installed', () => {
  const locations = ['oc-go-cc', '/tmp/oc-go-cc', path.join(process.env.HOME || '', '.local/bin/oc-go-cc')];
  for (const loc of locations) {
    try {
      const ver = execSync(`${loc} --version 2>/dev/null`, { encoding: 'utf8', timeout: 5000 }).trim();
      return { status: 'pass', message: `${ver} (${loc})` };
    } catch { /* try next */ }
  }
  return { status: 'fail', message: 'oc-go-cc not found. Install: https://github.com/The1Studio/oc-go-cc' };
});

// 3. API key
check('api-key-set', () => {
  if (process.env.OC_GO_CC_API_KEY) {
    return { status: 'pass', message: 'OC_GO_CC_API_KEY set' };
  }
  return { status: 'warn', message: 'OC_GO_CC_API_KEY not set' };
});

// 4. oc-go-cc config
check('oc-go-cc-config', () => {
  const configPath = path.join(process.env.HOME || '', '.config/oc-go-cc/config.json');
  if (fs.existsSync(configPath)) {
    return { status: 'pass', message: 'Config exists' };
  }
  return { status: 'fail', message: 'Config missing. Run: oc-go-cc init' };
});

// 5. CCS opencode-go profile
check('ccs-profile', () => {
  const settingsPath = path.join(process.env.HOME || '', '.ccs/opencode-go.settings.json');
  if (fs.existsSync(settingsPath)) {
    return { status: 'pass', message: 'Profile exists' };
  }
  return { status: 'fail', message: 'CCS opencode-go profile missing. Run: bash scripts/post-install.sh' };
});

// 6. Proxy health
check('proxy-health', () => {
  try {
    const resp = execSync('curl -s http://127.0.0.1:3456/health 2>/dev/null', { encoding: 'utf8', timeout: 3000 });
    const data = JSON.parse(resp);
    if (data.status === 'ok') {
      return { status: 'pass', message: `Proxy running (${data.metrics?.requests_received || 0} requests served)` };
    }
    return { status: 'warn', message: 'Proxy responded but status not ok' };
  } catch {
    return { status: 'warn', message: 'Proxy not running. Start: oc-go-cc serve --background' };
  }
});

// 7. Agent definitions (check cwd, project dir, and home)
check('agent-definitions', () => {
  const expected = ['mr-explorer-fast', 'mr-doc-scout', 'mr-doc-writer', 'mr-coder-cheap', 'mr-reviewer-deep', 'mr-tester'];
  const searchDirs = [
    path.join(process.cwd(), '.claude/agents'),
    path.join(process.env.CLAUDE_PROJECT_DIR || '', '.claude/agents'),
    path.join(process.env.HOME || '', '.claude/agents'),
  ].filter(Boolean);

  for (const dir of searchDirs) {
    const missing = expected.filter(a => !fs.existsSync(path.join(dir, `${a}.md`)));
    if (missing.length === 0) {
      return { status: 'pass', message: `${expected.length} agents found in ${dir}` };
    }
  }
  return { status: 'warn', message: 'Agents not found in cwd. Run install.sh in project root.' };
});

// 8. Skill
check('skill-installed', () => {
  const skillPath = path.join(process.cwd(), '.claude/skills/t1k-delegate/SKILL.md');
  if (fs.existsSync(skillPath)) {
    return { status: 'pass', message: 'Skill t1k-delegate installed' };
  }
  return { status: 'fail', message: 'Skill t1k-delegate missing' };
});

// 9. Delegate script
check('delegate-script', () => {
  const scriptPath = path.join(process.cwd(), 'scripts/mr-delegate.sh');
  if (fs.existsSync(scriptPath)) {
    try {
      fs.accessSync(scriptPath, fs.constants.X_OK);
      return { status: 'pass', message: 'mr-delegate.sh executable' };
    } catch {
      return { status: 'warn', message: 'mr-delegate.sh exists but not executable' };
    }
  }
  return { status: 'fail', message: 'mr-delegate.sh missing' };
});

// Output as JSON for t1k doctor to parse
console.log(JSON.stringify({ kit: 'theonekit-model-router', checks: results }, null, 2));

process.exit(hasFailure ? 1 : 0);
