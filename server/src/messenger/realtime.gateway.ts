import { Logger, UsePipes, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { ActorContext, UserRole } from '../common/security/actor-context';
import { RealtimeBus } from '../realtime/realtime-bus';
import { MessengerPolicy } from './messenger.policy';
import { JoinRoomPayload, PresencePayload, TypingPayload } from './dto/realtime-events.dto';

interface AccessTokenPayload {
  sub?: string;
  role?: UserRole;
}

/**
 * Вычисляет allowlist origin'ов для WebSocket-CORS из строки env
 * CORS_ALLOWED_ORIGINS (значения через запятую).
 *
 * - Непустой список → массив доверенных origin'ов.
 * - Пусто/не задано в production → false (CORS закрыт).
 * - Пусто/не задано вне production (dev) → true (для локальной разработки).
 */
export function resolveRealtimeCorsOrigin(
  allowedOrigins: string | undefined,
  nodeEnv: string | undefined = process.env.NODE_ENV
): string[] | boolean {
  const origins = (allowedOrigins ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);

  if (origins.length > 0) return origins;
  return nodeEnv === 'production' ? false : true;
}

interface RealtimeSocketData {
  actor?: ActorContext;
  rooms?: Set<string>;
  rate?: Map<string, { count: number; resetAt: number }>;
}

interface ClientToServerEvents {
  [event: string]: (...args: unknown[]) => void;
}

interface ServerToClientEvents {
  [event: string]: (payload: unknown) => void;
}

type RealtimeSocket = Socket<ClientToServerEvents, ServerToClientEvents, Record<string, never>, RealtimeSocketData>;

@WebSocketGateway({
  path: '/realtime',
  cors: {
    // CORS сокета ограничен allowlist'ом из CORS_ALLOWED_ORIGINS; вне prod
    // при пустом списке допускается true для локальной разработки.
    origin: resolveRealtimeCorsOrigin(process.env.CORS_ALLOWED_ORIGINS),
    credentials: true
  },
  pingInterval: 25_000,
  pingTimeout: 20_000
})
@UsePipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }))
export class RealtimeGateway
  implements OnGatewayConnection, OnGatewayDisconnect, OnGatewayInit
{
  @WebSocketServer()
  private server?: Server;

  private readonly logger = new Logger(RealtimeGateway.name);

  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly policy: MessengerPolicy,
    private readonly bus: RealtimeBus
  ) {}

  afterInit(server: Server): void {
    // Hand the Socket.IO server to the decoupled bus so CRM modules can
    // broadcast invalidation hints without depending on this gateway.
    this.bus.setServer(server);
  }

  async handleConnection(socket: RealtimeSocket): Promise<void> {
    const token = this.extractToken(socket);
    if (!token) {
      socket.disconnect(true);
      return;
    }

    try {
      const payload = await this.jwt.verifyAsync<AccessTokenPayload>(token, {
        secret: this.config.getOrThrow<string>('JWT_ACCESS_SECRET')
      });
      if (!payload.sub || !payload.role) {
        socket.disconnect(true);
        return;
      }

      socket.data.actor = { userId: payload.sub, role: payload.role };
      socket.data.rooms = new Set<string>();
      socket.data.rate = new Map();
      await socket.join(this.userRoom(payload.sub));
      // Staff receive CRM realtime invalidation hints (lessons/leads/etc.).
      if (payload.role !== 'client') {
        await socket.join(RealtimeBus.crmRoom);
      }
      this.logger.log(`Realtime connected user=${payload.sub}`);
    } catch {
      socket.disconnect(true);
    }
  }

  handleDisconnect(socket: RealtimeSocket): void {
    const actor = socket.data.actor;
    if (actor) this.publishPresence(actor.userId, 'offline', socket.data.rooms);
    socket.data.rooms?.clear();
  }

  @SubscribeMessage('room.join')
  async joinRoom(
    @ConnectedSocket() socket: RealtimeSocket,
    @MessageBody() payload: JoinRoomPayload
  ) {
    const actor = this.requireActor(socket);
    this.assertRate(socket, 'room.join', 20, 60_000);
    await this.policy.canJoinRealtimeRoom(actor, payload.roomType, payload.roomId);
    const room = payload.roomType === 'chat' ? this.chatRoom(payload.roomId) : this.userRoom(payload.roomId);
    await socket.join(room);
    socket.data.rooms?.add(room);
    return { ok: true, room };
  }

  @SubscribeMessage('room.leave')
  async leaveRoom(
    @ConnectedSocket() socket: RealtimeSocket,
    @MessageBody() payload: { roomId: string }
  ) {
    const room = payload.roomId.startsWith('chat:') || payload.roomId.startsWith('user:')
      ? payload.roomId
      : this.chatRoom(payload.roomId);
    await socket.leave(room);
    socket.data.rooms?.delete(room);
    return { ok: true };
  }

  @SubscribeMessage('typing.start')
  async typingStart(
    @ConnectedSocket() socket: RealtimeSocket,
    @MessageBody() payload: TypingPayload
  ) {
    const actor = this.requireActor(socket);
    this.assertRate(socket, 'typing', 60, 60_000);
    await this.policy.canJoinRealtimeRoom(actor, 'chat', payload.chatId);
    socket.to(this.chatRoom(payload.chatId)).emit('typing.start', {
      chatId: payload.chatId,
      userId: actor.userId
    });
    return { ok: true };
  }

  @SubscribeMessage('typing.stop')
  async typingStop(
    @ConnectedSocket() socket: RealtimeSocket,
    @MessageBody() payload: TypingPayload
  ) {
    const actor = this.requireActor(socket);
    this.assertRate(socket, 'typing', 60, 60_000);
    await this.policy.canJoinRealtimeRoom(actor, 'chat', payload.chatId);
    socket.to(this.chatRoom(payload.chatId)).emit('typing.stop', {
      chatId: payload.chatId,
      userId: actor.userId
    });
    return { ok: true };
  }

  @SubscribeMessage('presence.update')
  presenceUpdate(
    @ConnectedSocket() socket: RealtimeSocket,
    @MessageBody() payload: PresencePayload
  ) {
    const actor = this.requireActor(socket);
    this.assertRate(socket, 'presence', 30, 60_000);
    const status = payload.status ?? 'online';
    this.publishPresence(actor.userId, status, socket.data.rooms);
    return { ok: true, status };
  }

  publishChatEvent(chatId: string, event: string, payload: unknown): void {
    this.server?.to(this.chatRoom(chatId)).emit(event, payload);
  }

  publishUserEvent(userId: string, event: string, payload: unknown): void {
    this.server?.to(this.userRoom(userId)).emit(event, payload);
  }

  private publishPresence(userId: string, status: string, rooms?: Set<string>): void {
    const payload = { userId, status };
    this.publishUserEvent(userId, 'presence.updated', payload);
    for (const room of rooms ?? []) {
      if (room.startsWith('chat:')) {
        this.server?.to(room).emit('presence.updated', payload);
      }
    }
  }

  private requireActor(socket: RealtimeSocket): ActorContext {
    if (!socket.data.actor) {
      socket.disconnect(true);
      throw new Error('Unauthenticated realtime socket.');
    }
    return socket.data.actor;
  }

  private assertRate(socket: RealtimeSocket, key: string, max: number, windowMs: number): void {
    const now = Date.now();
    const rate = socket.data.rate ?? new Map<string, { count: number; resetAt: number }>();
    const bucket = rate.get(key);
    if (!bucket || bucket.resetAt <= now) {
      rate.set(key, { count: 1, resetAt: now + windowMs });
      socket.data.rate = rate;
      return;
    }
    bucket.count += 1;
    if (bucket.count > max) {
      socket.emit('rate_limited', { key });
      throw new Error('Realtime rate limit exceeded.');
    }
  }

  private extractToken(socket: RealtimeSocket): string | undefined {
    const authToken = socket.handshake.auth?.token;
    if (typeof authToken === 'string' && authToken.length > 0) return authToken;

    const authorization = socket.handshake.headers.authorization;
    if (!authorization) return undefined;
    const [scheme, token] = authorization.split(' ');
    if (scheme !== 'Bearer' || !token) return undefined;
    return token;
  }

  private chatRoom(chatId: string): string {
    return `chat:${chatId}`;
  }

  private userRoom(userId: string): string {
    return `user:${userId}`;
  }
}
