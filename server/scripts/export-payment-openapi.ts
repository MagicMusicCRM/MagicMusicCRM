import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createPaymentContractApp, paymentDocument } from './contracts/payment-contract-app';

async function main() {
  const app = await createPaymentContractApp();
  try {
    const output = resolve(__dirname, '../../contracts/payments.openapi.json');
    const serialized = JSON.stringify(paymentDocument(app), null, 2) + '\n';
    if (process.argv.includes('--check')) {
      if (readFileSync(output, 'utf8').replace(/\r\n/g, '\n') !== serialized) {
        throw new Error('Payment OpenAPI is stale. Run npm run contract:payments:export and review the change.');
      }
      console.log('Payment OpenAPI matches current controllers and DTOs.');
    } else {
      writeFileSync(output, serialized);
      console.log(output);
    }
  } finally { await app.close(); }
}
void main().catch(error => { console.error(error.message); process.exitCode = 1; });
