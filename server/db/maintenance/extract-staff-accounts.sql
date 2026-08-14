-- server/db/maintenance/extract-staff-accounts.sql
--
-- Выгружает учётки, которыми МОЖНО ВОЙТИ, в набор INSERT-ов — чтобы вернуть их
-- после перезаписи базы.
--
-- ЗАЧЕМ. При пересборке базы из HolliHop всё выводится детерминированно и
-- воспроизводится само: id педагогов совпали 24 из 24, учеников — 1035 из 1036.
-- Не воспроизводится ровно одно — то, что родилось в приложении, а не в
-- HolliHop: пароли.
--
-- КОГО БЕРЁМ. `password_hash is not null` — это и есть определение «можно
-- войти», а не список фамилий, который завтра устареет. На проде 17.07 таких
-- шесть: magic1–5 (тестовые по роли на каждую) и kvazar2727 (system_admin).
--
-- ⚠️ Остальные 1 072 пользователя войти НЕ МОГУТ: у них почта
-- `@migration.invalid` и пароля нет. В том числе все 12 менеджеров школы
-- (Мазалова, Богатырёва, Крошкин…) — они существуют записями, на которые
-- вешаются задачи, но в приложение не заходят. Это не побочный эффект
-- перезаписи: так на проде и было.
--
-- Зависимостей у шестерых нет: ни ученика, ни педагога, ни аватара (проверено).
-- Поэтому переносятся только `users` + `profiles`.
--
-- Usage (на исходной базе, до перезаписи):
--   psql ... -At -f extract-staff-accounts.sql > staff-accounts.sql
-- Затем, после перезаписи:
--   psql ... -f staff-accounts.sql

-- ⚠️ Опознаём по ПОЧТЕ, а не по id, и это не стилистика.
--
-- Первая редакция делала `on conflict (id)`. На проверке (для того она и была)
-- возврат упал: `kvazar2727@gmail.com` уже лежит в новой базе — он приезжает из
-- сида, — но с ДРУГИМ id (прод 8390798f…, сид 75e01fcf…). Конфликт по id не
-- срабатывал, и вставка билась о уникальный индекс по почте. На проде это
-- значило бы: база заменена, войти нельзя.
--
-- Почта и есть логин, так что она и есть тождество. Индекс частичный
-- (`where deleted_at is null`) — предикат обязателен, иначе Postgres не выведет
-- нужный индекс.
select format(
  'insert into app.users (id, email, password_hash, managed_password_ciphertext, full_name, phone, role, email_verified_at, profile_completed, created_at, updated_at, is_app_account, phone_verified_at, phone_normalized) values (%L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L) on conflict (lower(email)) where deleted_at is null do update set password_hash = excluded.password_hash, managed_password_ciphertext = excluded.managed_password_ciphertext, full_name = excluded.full_name, role = excluded.role, is_app_account = excluded.is_app_account, email_verified_at = excluded.email_verified_at, phone_verified_at = excluded.phone_verified_at;',
  u.id, u.email, u.password_hash, u.managed_password_ciphertext,
  u.full_name, u.phone, u.role,
  u.email_verified_at, u.profile_completed, u.created_at, u.updated_at,
  u.is_app_account, u.phone_verified_at, u.phone_normalized
)
from app.users u
where u.deleted_at is null
  and u.password_hash is not null

union all

-- Профиль — после пользователя: у него внешний ключ на users.
--
-- `user_id` берётся ПОДЗАПРОСОМ по почте, а не из выгрузки: если пользователь
-- уже был в базе, у него остался свой id, и ссылка на id прода упала бы внешним
-- ключом. Конфликт по user_id (индекс profiles_user_id_key) разрешается
-- обновлением — тогда уже существующий профиль просто дополняется.
select format(
  'insert into app.profiles (id, user_id, first_name, last_name, phone, dob, email_otp_2fa_enabled, custom_data, created_at, updated_at, phone_normalized) select %L, u.id, %L, %L, %L, %L, %L, %L, %L, %L, %L from app.users u where lower(u.email) = lower(%L) and u.deleted_at is null on conflict (user_id) do update set first_name = excluded.first_name, last_name = excluded.last_name, phone = excluded.phone, phone_normalized = excluded.phone_normalized;',
  p.id, p.first_name, p.last_name, p.phone, p.dob,
  p.email_otp_2fa_enabled, p.custom_data, p.created_at, p.updated_at,
  p.phone_normalized, u.email
)
from app.profiles p
join app.users u on u.id = p.user_id
where p.deleted_at is null
  and u.deleted_at is null
  and u.password_hash is not null;
