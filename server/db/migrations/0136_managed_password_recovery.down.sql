alter table app.users
  drop column if exists managed_password_ciphertext;
