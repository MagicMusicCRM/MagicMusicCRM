create extension if not exists btree_gist;

create table if not exists app.lesson_resource_bookings (
  lesson_id uuid not null references app.lessons(id) on delete cascade,
  resource_type text not null,
  resource_id uuid not null,
  occupied_at tstzrange not null,
  created_at timestamptz not null default now(),
  primary key (lesson_id, resource_type, resource_id),
  constraint lesson_resource_bookings_type_check check (
    resource_type in ('teacher', 'room', 'student', 'group')
  ),
  constraint lesson_resource_bookings_nonempty_check check (
    not isempty(occupied_at)
  )
);

insert into app.lesson_resource_bookings (
  lesson_id, resource_type, resource_id, occupied_at
)
select distinct
  lesson.id,
  resource.resource_type,
  resource.resource_id,
  tstzrange(
    lesson.scheduled_at,
    lesson.scheduled_at + lesson.duration_minutes * interval '1 minute',
    '[)'
  )
from app.lessons lesson
cross join lateral (
  select 'teacher'::text, lesson.teacher_id
  union all select 'room'::text, lesson.room_id
  union all select 'student'::text, lesson.student_id
  union all select 'group'::text, lesson.group_id
  union all
  select 'student'::text, participant.student_id
  from app.lesson_snapshot_participants participant
  where participant.lesson_id = lesson.id
  union all
  select 'student'::text, membership.student_id
  from app.group_students membership
  where membership.group_id = lesson.group_id
    and membership.left_at is null
    and not exists (
      select 1
      from app.lesson_snapshot_participants frozen
      where frozen.lesson_id = lesson.id
    )
) resource(resource_type, resource_id)
where lesson.deleted_at is null
  and lesson.status <> 'cancelled'
  and lesson.lifecycle_state = 'scheduled'
  and lesson.duration_minutes > 0
  and resource.resource_id is not null
on conflict (lesson_id, resource_type, resource_id) do update
set occupied_at = excluded.occupied_at;

do $$
declare
  overlap record;
begin
  select
    left_booking.resource_type,
    left_booking.resource_id,
    left_booking.lesson_id as left_lesson_id,
    right_booking.lesson_id as right_lesson_id
  into overlap
  from app.lesson_resource_bookings left_booking
  join app.lesson_resource_bookings right_booking
    on right_booking.resource_type = left_booking.resource_type
   and right_booking.resource_id = left_booking.resource_id
   and right_booking.lesson_id > left_booking.lesson_id
   and right_booking.occupied_at && left_booking.occupied_at
  order by left_booking.resource_type, left_booking.resource_id,
    left_booking.lesson_id, right_booking.lesson_id
  limit 1;

  if found then
    raise exception using
      errcode = '23P01',
      message = format(
        'lesson resource booking preflight failed: %s %s overlaps in lessons %s and %s',
        overlap.resource_type,
        overlap.resource_id,
        overlap.left_lesson_id,
        overlap.right_lesson_id
      ),
      hint = 'Resolve or explicitly reconcile existing schedule conflicts before applying migration 0137.';
  end if;
end $$;

alter table app.lesson_resource_bookings
  add constraint lesson_resource_bookings_no_overlap
  exclude using gist (
    resource_type with =,
    resource_id with =,
    occupied_at with &&
  )
  deferrable initially immediate;

create or replace function app.refresh_lesson_resource_bookings(
  target_lesson_id uuid
) returns void
language plpgsql
security definer
set search_path = pg_catalog, app
as $$
begin
  delete from app.lesson_resource_bookings booking
  where booking.lesson_id = target_lesson_id;

  insert into app.lesson_resource_bookings (
    lesson_id, resource_type, resource_id, occupied_at
  )
  select distinct
    lesson.id,
    resource.resource_type,
    resource.resource_id,
    tstzrange(
      lesson.scheduled_at,
      lesson.scheduled_at + lesson.duration_minutes * interval '1 minute',
      '[)'
    )
  from app.lessons lesson
  cross join lateral (
    select 'teacher'::text, lesson.teacher_id
    union all select 'room'::text, lesson.room_id
    union all select 'student'::text, lesson.student_id
    union all select 'group'::text, lesson.group_id
    union all
    select 'student'::text, participant.student_id
    from app.lesson_snapshot_participants participant
    where participant.lesson_id = lesson.id
    union all
    select 'student'::text, membership.student_id
    from app.group_students membership
    where membership.group_id = lesson.group_id
      and membership.left_at is null
      and not exists (
        select 1
        from app.lesson_snapshot_participants frozen
        where frozen.lesson_id = lesson.id
      )
  ) resource(resource_type, resource_id)
  where lesson.id = target_lesson_id
    and lesson.deleted_at is null
    and lesson.status <> 'cancelled'
    and lesson.lifecycle_state = 'scheduled'
    and lesson.duration_minutes > 0
    and resource.resource_id is not null;
end;
$$;

create or replace function app.lessons_refresh_resource_bookings_trigger()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, app
as $$
begin
  perform app.refresh_lesson_resource_bookings(
    case when tg_op = 'DELETE' then old.id else new.id end
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger lessons_refresh_resource_bookings
after insert or update of
  teacher_id, room_id, student_id, group_id, scheduled_at,
  duration_minutes, status, lifecycle_state, deleted_at
or delete on app.lessons
for each row execute function app.lessons_refresh_resource_bookings_trigger();

create or replace function app.lesson_participants_refresh_resource_bookings_trigger()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, app
as $$
begin
  perform app.refresh_lesson_resource_bookings(
    case when tg_op = 'DELETE' then old.lesson_id else new.lesson_id end
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger lesson_participants_refresh_resource_bookings
after insert or update or delete on app.lesson_snapshot_participants
for each row execute function app.lesson_participants_refresh_resource_bookings_trigger();

revoke execute on function app.refresh_lesson_resource_bookings(uuid)
  from public;
revoke execute on function app.lessons_refresh_resource_bookings_trigger()
  from public;
revoke execute on function app.lesson_participants_refresh_resource_bookings_trigger()
  from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    revoke insert, update, delete on app.lesson_resource_bookings
      from magiccrm_app;
    grant select on app.lesson_resource_bookings to magiccrm_app;
    revoke execute on function app.refresh_lesson_resource_bookings(uuid)
      from magiccrm_app;
    revoke execute on function app.lessons_refresh_resource_bookings_trigger()
      from magiccrm_app;
    revoke execute on function app.lesson_participants_refresh_resource_bookings_trigger()
      from magiccrm_app;
  end if;
end $$;
