-- Скрипт полного удаления всех политик (чтобы точно удалить те, имена которых мы не помним)
DO $$ 
DECLARE
    pol RECORD;
BEGIN
    -- Удаляем все политики для group_chat_members
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'group_chat_members' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.group_chat_members', pol.policyname);
    END LOOP;
    
    -- Удаляем все политики для group_chats (на всякий случай)
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'group_chats' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.group_chats', pol.policyname);
    END LOOP;
END $$;

-- Теперь устанавливаем чистые простые политики без рекурсии для group_chat_members
CREATE POLICY "members_select" ON public.group_chat_members FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "members_insert" ON public.group_chat_members FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "members_update" ON public.group_chat_members FOR UPDATE USING (auth.uid() IS NOT NULL);
CREATE POLICY "members_delete" ON public.group_chat_members FOR DELETE USING (auth.uid() IS NOT NULL);

-- Устанавливаем чистые политики для group_chats
CREATE POLICY "chats_select" ON public.group_chats FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "chats_insert" ON public.group_chats FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "chats_update" ON public.group_chats FOR UPDATE USING (auth.uid() IS NOT NULL);
CREATE POLICY "chats_delete" ON public.group_chats FOR DELETE USING (auth.uid() IS NOT NULL);
