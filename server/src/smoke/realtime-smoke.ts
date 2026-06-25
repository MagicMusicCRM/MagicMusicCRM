import { io, Socket } from "socket.io-client";

interface AuthSession {
  accessToken: string;
}

interface AuthResponse {
  user: { id: string; email: string; role: string };
  session?: AuthSession;
}

interface ChatResponse {
  id: string;
  type?: string;
  title?: string | null;
}

interface MaskedSender {
  id: string | null;
  name?: string;
  firstName?: string | null;
  lastName?: string | null;
  email?: string | null;
}

interface MaskedMessageResponse extends MessageResponse {
  sender?: MaskedSender | null;
  senderId?: string | null;
}

interface MessageResponse {
  id: string;
  chatId: string;
  content: string | null;
}

interface ChannelResponse {
  id: string;
  title: string;
}

interface ChannelPostResponse {
  id: string;
  channelId: string;
  content: string;
}

const apiBaseUrl = normalizeBaseUrl(
  process.env.REALTIME_SMOKE_API_BASE_URL ?? "https://api.phantom-net.ru/api",
);
const password =
  process.env.REALTIME_SMOKE_PASSWORD ?? `Smoke${Date.now()}!Aa1`;
const email =
  process.env.REALTIME_SMOKE_EMAIL ??
  `realtime-smoke-${Date.now()}@example.com`;

async function main() {
  const steps: Record<string, unknown> = {};
  await request("GET", "/health");

  if (!process.env.REALTIME_SMOKE_EMAIL) {
    await request("POST", "/auth/signup", {
      email,
      password,
      fullName: "Realtime Smoke",
    });
  }

  const login = await request<AuthResponse>("POST", "/auth/login", {
    email,
    password,
  });
  const accessToken = login.session?.accessToken;
  if (!accessToken) throw new Error("Login did not return an access token.");

  const chat = await request<ChatResponse>(
    "POST",
    "/messenger/chats/direct",
    { type: "administration" },
    accessToken,
  );

  // The default "Объявления" channel must be visible to a plain client.
  const channels = await request<{ items: ChannelResponse[] }>(
    "GET",
    "/messenger/channels",
    undefined,
    accessToken,
  );
  const announcements = channels.items.find((c) => c.title === "Объявления");
  if (!announcements) {
    throw new Error('Default "Объявления" channel not visible to client.');
  }
  steps.announcementsChannelId = announcements.id;

  const socket = await connectRealtime(accessToken);

  // Optional staff session (no secrets committed): enables the full
  // staff<->client + announcements-post scenarios when provided.
  const staffEmail = process.env.REALTIME_SMOKE_STAFF_EMAIL;
  const staffPassword = process.env.REALTIME_SMOKE_STAFF_PASSWORD;
  let staffSocket: Socket | undefined;
  let staffToken: string | undefined;
  if (staffEmail && staffPassword) {
    const staffLogin = await request<AuthResponse>("POST", "/auth/login", {
      email: staffEmail,
      password: staffPassword,
    });
    staffToken = staffLogin.session?.accessToken;
    if (!staffToken) throw new Error("Staff login did not return a token.");
    staffSocket = await connectRealtime(staffToken);
  }

  try {
    // ── Client joins its own administration chat + announcements channel. ──
    await emitWithAck(socket, "room.join", {
      roomType: "chat",
      roomId: chat.id,
    });
    const joinAck = await emitWithAck(socket, "room.join", {
      roomType: "channel",
      roomId: announcements.id,
    });
    steps.clientJoinedAnnouncements = joinAck;

    // Client must be in its user room to receive chat.created / chat.removed events.
    await emitWithAck(socket, "room.join", {
      roomType: "user",
      roomId: login.user.id,
    });

    // ── Client -> (administration) self echo (baseline). ──
    const content = `realtime-smoke-${Date.now()}`;
    const eventPromise = waitForMessageCreated(socket, chat.id, content);
    const sent = await request<MessageResponse>(
      "POST",
      `/messenger/chats/${chat.id}/messages`,
      { content, messageType: "text" },
      accessToken,
    );
    const event = await eventPromise;
    steps.adminEcho = { messageId: sent.id, eventMessageId: event.id };

    // ── Client cannot write the announcements channel (expect 403). ──
    steps.announcementsClientForbidden = await expectForbidden(
      "POST",
      `/messenger/channels/${announcements.id}/posts`,
      { content: "client must be blocked" },
      accessToken,
    );

    // ── Staff-dependent scenarios. ──
    if (staffSocket && staffToken) {
      // Staff sees the administration inbox surface; join the conversation.
      await emitWithAck(staffSocket, "room.join", {
        roomType: "chat",
        roomId: chat.id,
      });

      // Client -> staff: staff receives message.created without refresh.
      const toStaff = `to-staff-${Date.now()}`;
      const staffRecv = waitForEvent<MessageResponse>(
        staffSocket,
        "message.created",
        (p) => p.chatId === chat.id && p.content === toStaff,
      );
      await request(
        "POST",
        `/messenger/chats/${chat.id}/messages`,
        { content: toStaff, messageType: "text" },
        accessToken,
      );
      steps.clientToStaff = await staffRecv;

      // Staff -> client: client receives the reply without refresh.
      const toClient = `to-client-${Date.now()}`;
      const clientRecv = waitForEvent<MessageResponse>(
        socket,
        "message.created",
        (p) => p.chatId === chat.id && p.content === toClient,
      );
      await request(
        "POST",
        `/messenger/chats/${chat.id}/messages`,
        { content: toClient, messageType: "text" },
        staffToken,
      );
      steps.staffToClient = await clientRecv;

      // Staff posts to announcements: client receives channel.post_created.
      const postContent = `announcement-${Date.now()}`;
      const postRecv = waitForEvent<ChannelPostResponse>(
        socket,
        "channel.post_created",
        (p) => p.channelId === announcements.id && p.content === postContent,
      );
      const post = await request<ChannelPostResponse>(
        "POST",
        `/messenger/channels/${announcements.id}/posts`,
        { content: postContent },
        staffToken,
      );
      steps.announcementPostId = post.id;
      steps.clientReceivedPost = await postRecv;

      // ── Assign → masked staff reply. ──
      // Staff claims the administration chat. The client must never receive
      // the real staff identity — toMessageDto masks the sender to
      // { id: null, name: "Администрация", ... } with senderId: null.
      await request("POST", `/messenger/chats/${chat.id}/assign`, {}, staffToken);
      steps.assigned = true;

      const masked = `masked-reply-${Date.now()}`;
      const clientMaskedRecv = waitForEvent<MaskedMessageResponse>(
        socket,
        "message.created",
        (p) => p.chatId === chat.id && p.content === masked,
      );
      await request(
        "POST",
        `/messenger/chats/${chat.id}/messages`,
        { content: masked, messageType: "text" },
        staffToken,
      );
      const maskedEvent = await clientMaskedRecv;
      // Assert masking: sender.name MUST be "Администрация" and sender.id / senderId MUST be null.
      // If real staff identity leaks (Phase 3 regression), this throws — smoke fails immediately.
      const senderName = maskedEvent.sender?.name;
      const senderId =
        maskedEvent.sender?.id !== undefined
          ? maskedEvent.sender.id
          : (maskedEvent.senderId ?? null);
      if (senderName !== "Администрация" || senderId !== null) {
        throw new Error(
          `Staff identity leaked to client: sender=${JSON.stringify(maskedEvent.sender)} senderId=${String(senderId)}`,
        );
      }
      steps.maskedStaffReply = { ok: true };

      // ── Group create → client receives chat.created; leave → chat.removed. ──
      // Staff creates a group that includes the client; the client must receive
      // chat.created on its user room. Then the client leaves; it receives chat.removed.
      const groupName = `smoke-group-${Date.now()}`;
      const groupCreated = waitForEvent<ChatResponse>(
        socket,
        "chat.created",
        (p) => !!p.id && p.title === groupName,
        15_000,
      );
      const group = await request<ChatResponse>(
        "POST",
        "/messenger/groups",
        { name: groupName, memberUserIds: [login.user.id] },
        staffToken,
      );
      steps.groupCreatedEvent = await groupCreated; // client saw the new group live
      steps.groupId = group.id;

      // Client leaves → user room receives chat.removed { id }.
      const groupRemoved = waitForEvent<{ id: string }>(
        socket,
        "chat.removed",
        (p) => p.id === group.id,
        15_000,
      );
      await request(
        "POST",
        `/messenger/groups/${group.id}/leave`,
        {},
        accessToken,
      );
      steps.groupRemovedEvent = await groupRemoved;
    } else {
      steps.staffScenarios =
        "skipped (set REALTIME_SMOKE_STAFF_EMAIL/REALTIME_SMOKE_STAFF_PASSWORD to run)";
    }

    console.log(
      JSON.stringify({
        ok: true,
        apiBaseUrl,
        userId: login.user.id,
        chatId: chat.id,
        ...steps,
      }),
    );
  } finally {
    socket.disconnect();
    staffSocket?.disconnect();
  }
}

async function request<T>(
  method: string,
  path: string,
  body?: unknown,
  accessToken?: string,
): Promise<T> {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    method,
    headers: {
      ...(body ? { "Content-Type": "application/json" } : {}),
      ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  const text = await response.text();
  const data = text ? JSON.parse(text) : undefined;
  if (!response.ok) {
    throw new Error(
      `HTTP ${response.status} ${method} ${path}: ${JSON.stringify(data)}`,
    );
  }
  return data as T;
}

function connectRealtime(accessToken: string): Promise<Socket> {
  const socket = io(realtimeOrigin(apiBaseUrl), {
    transports: ["websocket"],
    path: "/realtime",
    auth: { token: accessToken },
    autoConnect: false,
    timeout: 10_000,
  });

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.disconnect();
      reject(new Error("Realtime connection timed out."));
    }, 12_000);

    socket.once("connect", () => {
      clearTimeout(timer);
      resolve(socket);
    });
    socket.once("connect_error", (error) => {
      clearTimeout(timer);
      socket.disconnect();
      reject(error);
    });
    socket.connect();
  });
}

function emitWithAck(
  socket: Socket,
  event: string,
  payload: Record<string, unknown>,
): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`${event} ack timed out.`)),
      10_000,
    );
    socket.emit(event, payload, (ack: unknown) => {
      clearTimeout(timer);
      resolve(ack);
    });
  });
}

function waitForMessageCreated(
  socket: Socket,
  chatId: string,
  content: string,
): Promise<MessageResponse> {
  return waitForEvent<MessageResponse>(
    socket,
    "message.created",
    (payload) => payload.chatId === chatId && payload.content === content,
  );
}

function waitForEvent<T>(
  socket: Socket,
  event: string,
  predicate: (payload: T) => boolean,
  timeoutMs = 15_000,
): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`${event} event timed out.`)),
      timeoutMs,
    );
    socket.on(event, (payload: T) => {
      if (!predicate(payload)) return;
      clearTimeout(timer);
      resolve(payload);
    });
  });
}

/** Asserts a write is rejected with HTTP 403 (RBAC). Returns true on success. */
async function expectForbidden(
  method: string,
  path: string,
  body: unknown,
  accessToken: string,
): Promise<true> {
  try {
    await request(method, path, body, accessToken);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.includes("HTTP 403")) return true;
    throw new Error(`Expected HTTP 403 for ${method} ${path}, got: ${message}`);
  }
  throw new Error(`Expected HTTP 403 for ${method} ${path}, but it succeeded.`);
}

function normalizeBaseUrl(value: string): string {
  const trimmed = value.trim();
  return trimmed.endsWith("/") ? trimmed.slice(0, -1) : trimmed;
}

function realtimeOrigin(value: string): string {
  const url = new URL(value);
  return `${url.protocol}//${url.host}`;
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
