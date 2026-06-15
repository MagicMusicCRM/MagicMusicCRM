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
}

interface MessageResponse {
  id: string;
  chatId: string;
  content: string | null;
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

  const socket = await connectRealtime(accessToken);
  try {
    await emitWithAck(socket, "room.join", {
      roomType: "chat",
      roomId: chat.id,
    });

    const content = `realtime-smoke-${Date.now()}`;
    const eventPromise = waitForMessageCreated(socket, chat.id, content);
    const sent = await request<MessageResponse>(
      "POST",
      `/messenger/chats/${chat.id}/messages`,
      { content, messageType: "text" },
      accessToken,
    );
    const event = await eventPromise;

    console.log(
      JSON.stringify({
        ok: true,
        apiBaseUrl,
        userId: login.user.id,
        chatId: chat.id,
        messageId: sent.id,
        eventMessageId: event.id,
      }),
    );
  } finally {
    socket.disconnect();
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
  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error("message.created event timed out.")),
      15_000,
    );
    socket.on("message.created", (payload: MessageResponse) => {
      if (payload.chatId !== chatId || payload.content !== content) return;
      clearTimeout(timer);
      resolve(payload);
    });
  });
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
