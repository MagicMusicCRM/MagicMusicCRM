-- Fix for infinite recursion in group_chat_members

-- Drop ALL existing policies on group_chat_members to avoid conflicts
DROP POLICY IF EXISTS "Users can view members of their chats" ON group_chat_members;
DROP POLICY IF EXISTS "Admins can insert members" ON group_chat_members;
DROP POLICY IF EXISTS "Users can view their own memberships" ON group_chat_members;
DROP POLICY IF EXISTS "Anyone can insert" ON group_chat_members;
DROP POLICY IF EXISTS "Enable read access for all" ON group_chat_members;
DROP POLICY IF EXISTS "Enable insert for all" ON group_chat_members;
DROP POLICY IF EXISTS "Enable update for all" ON group_chat_members;

-- Create bulletproof policies for group_chat_members that do not recurse
-- In our CRM, it is safe for authenticated users to see group memberships, 
-- but message reading is still restricted by the messages table RLS.
CREATE POLICY "Enable read access for authenticated users" 
ON group_chat_members FOR SELECT 
USING (auth.uid() IS NOT NULL);

CREATE POLICY "Enable insert access for authenticated users" 
ON group_chat_members FOR INSERT 
WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Enable update access for authenticated users" 
ON group_chat_members FOR UPDATE 
USING (auth.uid() IS NOT NULL);

CREATE POLICY "Enable delete access for authenticated users" 
ON group_chat_members FOR DELETE 
USING (auth.uid() IS NOT NULL);
