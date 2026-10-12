const { execFileSync } = require('child_process');

const PORT = process.env.MB_VM_SSH_PORT || '2222';
const HOST = process.env.MB_VM_SSH_HOST || 'root@localhost';
const PASS = process.env.MB_VM_SSH_PASS || 'root';
const REMOTE_OK = process.env.MB_UI_DIFF_REMOTE_HOOKS === '1';
const OPTS = [
  '-o',
  'StrictHostKeyChecking=no',
  '-o',
  'UserKnownHostsFile=/dev/null',
  '-o',
  'LogLevel=ERROR',
  '-p',
  PORT,
  HOST,
];

function local(host) {
  return /@(localhost|127\.0\.0\.1)$/.test(host);
}

function sh(script, label) {
  try {
    execFileSync('sshpass', ['-e', 'ssh'].concat(OPTS, ['sh -s']), {
      input: 'set -e\n' + script,
      env: Object.assign({}, process.env, { SSHPASS: PASS, SSH_AUTH_SOCK: '' }),
      stdio: ['pipe', 'ignore', 'pipe'],
      timeout: 30000,
    });
  } catch (e) {
    throw new Error(
      `${label}: vm hook failed: ${
        String(e.stderr || e.message)
          .trim()
          .split('\n')[0]
      }`,
    );
  }
}

async function around(entry, run) {
  if (!entry.setup) return run();
  if (!local(HOST) && !REMOTE_OK)
    throw new Error(`${entry.label}: vm hooks change ${HOST}; set MB_UI_DIFF_REMOTE_HOOKS=1 to allow a non-local host`);
  let failed = null;
  let result;

  try {
    sh(entry.setup, entry.label + ' setup');
    result = await run();
  } catch (e) {
    failed = e;
  }
  try {
    sh(entry.teardown, entry.label + ' teardown');
  } catch (e) {
    if (failed) console.error(e.message);
    else failed = e;
  }
  if (failed) throw failed;

  return result;
}

module.exports = { around };
