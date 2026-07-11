-- KVA-239: новая роль «Директор» (director) в иерархии
-- client < teacher < admin < manager < director < system_admin.
-- Сид директора намеренно отсутствует: владелец назначает роль вручную.
alter type app.user_role add value if not exists 'director';
