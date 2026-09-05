import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createExpenseContractApp, expenseDocument } from './contracts/expense-contract-app';

async function main() {
  const app = await createExpenseContractApp();
  try {
    const output = resolve(__dirname, '../../contracts/expenses.openapi.json');
    const serialized = JSON.stringify(expenseDocument(app), null, 2) + '\n';
    if (process.argv.includes('--check')) {
      if (readFileSync(output, 'utf8').replace(/\r\n/g, '\n') !== serialized) {
        throw new Error('Expense OpenAPI is stale. Run npm run contract:export and review the change.');
      }
      console.log('Expense OpenAPI matches current controllers and DTOs.');
    } else {
      writeFileSync(output, serialized);
      console.log(output);
    }
  } finally { await app.close(); }
}
void main().catch(error => { console.error(error.message); process.exitCode = 1; });
