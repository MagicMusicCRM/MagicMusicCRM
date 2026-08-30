do $$
begin
  if exists (
    select 1
    from app.students student
    where student.contact_email is not null
      and not exists (
        select 1
        from app.profiles profile
        join app.users account
          on account.id = profile.user_id
         and account.deleted_at is null
        where profile.id = student.profile_id
          and profile.deleted_at is null
          and lower(btrim(account.email)) = lower(btrim(student.contact_email))
      )
  ) then
    raise exception
      '0145 down migration blocked: contact email exists outside app.users; use a contact-aware server rollback';
  end if;
end $$;

drop index if exists app.students_contact_email_lower_idx;
drop index if exists app.email_outbox_recipient_student_idx;

alter table app.email_outbox
  drop column if exists recipient_student_id;

alter table app.students
  drop column if exists contact_email;
