alter table app.users
  add column if not exists managed_password_ciphertext text;

comment on column app.users.managed_password_ciphertext is
  'AES-256-GCM envelope for explicit Director/system_admin credential reveal; authentication uses password_hash.';
