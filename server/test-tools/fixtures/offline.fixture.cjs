const {Pool, Client} = require('pg');

test('offline guard refuses actual pg entry points before a network connection', async () => {
  const pool = new Pool();
  const client = new Client();
  for (const connect of [() => pool.connect(), () => pool.query('select 1'), () => client.connect(), () => client.query('select 1')]) {
    expect(connect).toThrow('PostgreSQL access is disabled');
  }
  await pool.end();
});
