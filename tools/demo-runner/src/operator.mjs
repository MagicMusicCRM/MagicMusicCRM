import readline from 'node:readline/promises';

export async function waitForOperator(message, { confirmation = false } = {}) {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    throw new Error(`Manual placeholder requires an interactive terminal: ${message}`);
  }
  const interface_ = readline.createInterface({ input: process.stdin, output: process.stdout });
  try {
    const suffix = confirmation ? '\nType YES after verifying this state: ' : '\nPress ENTER when the displayed action is complete: ';
    const answer = await interface_.question(`[manual placeholder] ${message}${suffix}`);
    return confirmation ? answer.trim().toUpperCase() === 'YES' : true;
  } finally {
    interface_.close();
  }
}
