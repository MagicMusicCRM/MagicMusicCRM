update app.chats
set title = 'Administration',
    updated_at = now()
where type = 'administration'
  and title = 'Администрация';
