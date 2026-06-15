create index if not exists audit_events_auth_email_hash_created_idx
  on app.audit_events (action, (metadata ->> 'emailHash'), created_at desc)
  where action in (
    'auth.login_failed',
    'auth.otp_verify_failed',
    'auth.login_rate_limited',
    'auth.otp_verify_rate_limited'
  );
