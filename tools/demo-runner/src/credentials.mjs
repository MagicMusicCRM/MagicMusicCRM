import readline from 'node:readline';

function promptLine(prompt) {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    throw new Error(`Missing credential in a non-interactive terminal: ${prompt}`);
  }
  const interface_ = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    interface_.question(prompt, (answer) => {
      interface_.close();
      resolve(answer);
    });
  });
}

function promptSecret(prompt) {
  if (!process.stdin.isTTY || !process.stdout.isTTY || typeof process.stdin.setRawMode !== 'function') {
    throw new Error(`Missing password in a non-interactive terminal: ${prompt}`);
  }

  return new Promise((resolve, reject) => {
    let value = '';
    process.stdout.write(prompt);
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdin.setEncoding('utf8');

    const cleanup = () => {
      process.stdin.off('data', onData);
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stdout.write('\n');
    };

    const onData = (chunk) => {
      if (chunk === '\u0003') {
        cleanup();
        reject(new Error('Credential prompt interrupted.'));
        return;
      }
      if (chunk === '\r' || chunk === '\n') {
        cleanup();
        resolve(value);
        return;
      }
      if (chunk === '\u0008' || chunk === '\u007f') {
        if (value.length > 0) {
          value = value.slice(0, -1);
          process.stdout.write('\b \b');
        }
        return;
      }
      value += chunk;
      process.stdout.write('*');
    };

    process.stdin.on('data', onData);
  });
}

export class CredentialProvider {
  #cache = new Map();
  #redactionValues = new Set();

  constructor({ roleConfig, vault }) {
    this.roleConfig = roleConfig;
    this.vault = vault;
  }

  async get(role) {
    if (this.#cache.has(role)) return this.#cache.get(role);
    const config = this.roleConfig[role];
    if (!config) throw new Error(`Unknown credential role: ${role}`);

    const loginKey = `${config.credentialPrefix}_LOGIN`;
    const passwordKey = `${config.credentialPrefix}_PASSWORD`;
    const login = process.env[loginKey] || await promptLine(`${config.avdName} login: `);
    const password = process.env[passwordKey] || await promptSecret(`${config.avdName} password: `);
    if (!login || !password) throw new Error(`Empty runtime credential for ${config.avdName}.`);

    this.vault.add(login);
    this.vault.add(password);
    this.#redactionValues.add(login);
    this.#redactionValues.add(password);
    const credentials = { login, password };
    this.#cache.set(role, credentials);
    return credentials;
  }

  release(role) {
    const credentials = this.#cache.get(role);
    if (!credentials) return;
    credentials.login = '';
    credentials.password = '';
    this.#cache.delete(role);
  }

  clear() {
    for (const role of [...this.#cache.keys()]) this.release(role);
    for (const value of this.#redactionValues) this.vault.delete(value);
    this.#redactionValues.clear();
  }
}
