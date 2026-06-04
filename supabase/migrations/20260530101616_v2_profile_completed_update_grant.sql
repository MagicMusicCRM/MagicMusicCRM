grant update (
  first_name,
  last_name,
  phone,
  dob,
  avatar_url,
  fcm_token,
  last_seen_at,
  profile_completed_at
)
on table public.profiles to authenticated;
