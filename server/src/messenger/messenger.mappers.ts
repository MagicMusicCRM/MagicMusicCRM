// Shared row shapes for the messenger aggregate and their pure DTO
// projections. Presentation-only: no injected state, no side effects. Imported
// by MessengerService and the extracted message/read-receipt services so the
// administration-chat sender-masking rule lives in exactly one place.

export interface ChatRow {
  id: string;
  type: string;
  title: string | null;
  created_by: string | null;
  last_message_id: string | null;
  last_message_content: string | null;
  last_message_created_at: Date | string | null;
  unread_count: string | null;
  is_muted: boolean | null;
  partner_user_id?: string | null;
  partner_email?: string | null;
  partner_first_name?: string | null;
  partner_last_name?: string | null;
  partner_avatar_file_id?: string | null;
  created_at: Date | string;
  updated_at: Date | string;
  // Exact PostgreSQL timestamptz projection used only for keyset cursors.
  // The pg JS Date parser truncates microseconds, so cursor code must never
  // derive its boundary from `updated_at`.
  cursor_updated_at?: string;
  slug?: string | null;
  is_system?: boolean | null;
  // Staff inbox fields (administration chats only)
  owner_first_name?: string | null;
  owner_last_name?: string | null;
  assigned_to_user_id?: string | null;
  assigned_first_name?: string | null;
  assigned_last_name?: string | null;
  folder?: string | null;
  archived_at?: Date | string | null;
  branch_id?: string | null;
  branch_name?: string | null;
}

export interface MessageRow {
  id: string;
  chat_id: string;
  sender_id: string | null;
  content: string | null;
  message_type: string;
  attachment_file_id: string | null;
  reply_to_id: string | null;
  forwarded_from_id: string | null;
  pinned_by: string | null;
  pinned_at: Date | string | null;
  created_at: Date | string;
  updated_at: Date | string;
  deleted_at: Date | string | null;
  sender_email: string | null;
  sender_first_name: string | null;
  sender_last_name: string | null;
  sender_role?: string | null;
  sender_avatar_file_id?: string | null;
  attachment_original_name?: string | null;
  attachment_mime_type?: string | null;
  attachment_size_bytes?: string | number | null;
  is_read: boolean | null;
  reactions?: Array<{ emoji: string; count: number; reactedByMe: boolean }> | null;
}

export interface ChatMemberRow {
  profile_id: string | null;
  user_id: string;
  email: string | null;
  role: string;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  avatar_file_id: string | null;
  joined_at: Date | string;
}

export function toChatSummaryDto(
  row: ChatRow,
  opts?: { canWrite?: boolean },
) {
    const ownerFullName = [row.owner_first_name, row.owner_last_name]
      .filter(Boolean)
      .join(" ")
      .trim() || null;
    const assignedFullName = [row.assigned_first_name, row.assigned_last_name]
      .filter(Boolean)
      .join(" ")
      .trim() || null;
    return {
      id: row.id,
      type: row.type,
      title: row.title,
      createdBy: row.created_by,
      lastMessageId: row.last_message_id,
      lastMessageContent: row.last_message_content,
      lastMessageCreatedAt: row.last_message_created_at,
      partnerId: row.partner_user_id ?? null,
      partner: row.partner_user_id
        ? {
            id: row.partner_user_id,
            email: row.partner_email ?? null,
            firstName: row.partner_first_name ?? null,
            lastName: row.partner_last_name ?? null,
            avatarFileId: row.partner_avatar_file_id ?? null,
          }
        : null,
      unreadCount: Number(row.unread_count ?? "0"),
      isMuted: row.is_muted == true,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      ownerName: ownerFullName,
      assignedTo: row.assigned_to_user_id
        ? { id: row.assigned_to_user_id, name: assignedFullName }
        : null,
      folder: row.folder ?? null,
      archived: row.archived_at != null,
      branchId: row.branch_id ?? null,
      branchName: row.branch_name ?? null,
      slug: row.slug ?? null,
      isSystem: row.is_system == true,
      // Server-declared composer visibility («Объявления» are read-only for
      // non-manager roles). Default true: callers that cannot compute it
      // (fan-out paths) must not accidentally hide the composer.
      canWrite: opts?.canWrite ?? true,
    };
}

export function toMessageDto(
    row: MessageRow,
    opts?: { maskStaffSender?: boolean },
  ) {
    // When masking, the staff sender is collapsed into the anonymous
    // "Администрация" identity and the real senderId is withheld.
    const masked = opts?.maskStaffSender === true;
    return {
      id: row.id,
      chatId: row.chat_id,
      senderId: masked ? null : row.sender_id,
      sender: masked
        ? {
            id: null,
            name: "Администрация",
            firstName: null,
            lastName: null,
            email: null,
            role: null,
            avatarFileId: null,
          }
        : row.sender_id
          ? {
              id: row.sender_id,
              email: row.sender_email,
              firstName: row.sender_first_name,
              lastName: row.sender_last_name,
              role: row.sender_role ?? null,
              avatarFileId: row.sender_avatar_file_id ?? null,
            }
          : null,
      content: row.deleted_at ? null : row.content,
      messageType: row.message_type,
      attachmentFileId: row.deleted_at ? null : row.attachment_file_id,
      attachmentName: row.deleted_at ? null : (row.attachment_original_name ?? null),
      attachmentMimeType: row.deleted_at ? null : (row.attachment_mime_type ?? null),
      attachmentSize: row.deleted_at
        ? null
        : row.attachment_size_bytes == null
          ? null
          : Number(row.attachment_size_bytes),
      attachment: row.deleted_at || !row.attachment_file_id
        ? null
        : {
            id: row.attachment_file_id,
            originalFileName: row.attachment_original_name ?? null,
            mimeType: row.attachment_mime_type ?? null,
            sizeBytes: row.attachment_size_bytes == null ? null : Number(row.attachment_size_bytes),
          },
      replyToId: row.reply_to_id,
      forwardedFromId: row.forwarded_from_id,
      pinnedBy: row.pinned_by,
      pinnedAt: row.pinned_at,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      deletedAt: row.deleted_at,
      isRead: row.is_read == true,
      reactions: row.deleted_at ? [] : (row.reactions ?? []),
    };
}

export function toChatMemberDto(row: ChatMemberRow, currentUserId: string) {
    return {
      profileId: row.profile_id,
      userId: row.user_id,
      email: row.email,
      role: row.role,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      avatarFileId: row.avatar_file_id,
      joinedAt: row.joined_at,
      isCurrentUser: row.user_id === currentUserId,
    };
}
