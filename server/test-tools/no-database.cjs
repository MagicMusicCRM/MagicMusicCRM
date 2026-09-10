// Offline selections must never silently use a developer database.
jest.mock('pg', () => {
  const actual = jest.requireActual('pg');
  const denied = () => { throw new Error('PostgreSQL access is disabled for this explicitly offline test selection.'); };
  return {
    ...actual,
    Pool: class extends actual.Pool { connect() { return denied(); } query() { return denied(); } },
    Client: class extends actual.Client { connect() { return denied(); } query() { return denied(); } },
  };
});
