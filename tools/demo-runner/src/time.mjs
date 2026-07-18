export const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

export async function poll(predicate, {
  timeoutMs = 20_000,
  intervalMs = 250,
  description = 'condition',
} = {}) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      if (await predicate()) return true;
    } catch (error) {
      lastError = error;
    }
    await sleep(intervalMs);
  }
  const suffix = lastError ? ` Last error: ${lastError.message}` : '';
  throw new Error(`Timed out after ${timeoutMs} ms waiting for ${description}.${suffix}`);
}
