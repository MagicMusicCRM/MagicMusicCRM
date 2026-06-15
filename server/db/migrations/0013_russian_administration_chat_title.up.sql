update app.chats
set title = 'Администрация',
    updated_at = now()
where type = 'administration'
  and (title is null or title = '' or title = 'Administration');
