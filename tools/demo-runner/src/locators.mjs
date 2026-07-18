export function locatorSelector(locator) {
  if (!locator || typeof locator.value !== 'string' || locator.value.length === 0) {
    throw new Error('A locator must contain a non-empty value.');
  }
  switch (locator.using) {
    case 'accessibility id':
      return `~${locator.value}`;
    case 'id':
      return `id=${locator.value}`;
    case 'android uiautomator':
      return `android=${locator.value}`;
    case 'xpath':
      return locator.value;
    default:
      throw new Error(`Unsupported locator strategy: ${locator.using}`);
  }
}

export async function findElement(driver, locator, {
  timeoutMs = 20_000,
  displayed = true,
  reverse = false,
} = {}) {
  const element = await driver.$(locatorSelector(locator));
  await element.waitForDisplayed({ timeout: timeoutMs, reverse });
  if (displayed && !reverse && !await element.isDisplayed()) {
    throw new Error(`Element is not displayed: ${locator.value}`);
  }
  return element;
}

export async function isDisplayed(driver, locator) {
  try {
    const element = await driver.$(locatorSelector(locator));
    return await element.isDisplayed();
  } catch {
    return false;
  }
}
