import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { cert, getApps, initializeApp } from "npm:firebase-admin@12.7.0/app";
import { getMessaging } from "npm:firebase-admin@12.7.0/messaging";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-notification-dispatch-secret",
};

type NotificationPayload = {
  userIds?: unknown;
  title?: unknown;
  body?: unknown;
  sender_id?: unknown;
  chat_id?: unknown;
  receiver_id?: unknown;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const dispatchSecret = Deno.env.get("NOTIFICATION_DISPATCH_SECRET") ?? "";
const firebaseServiceAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "";

const adminClient = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (!(await isAuthorizedDispatch(req))) {
      return json({ error: "forbidden" }, 403);
    }

    const payload = await readPayload(req);
    if (payload.userIds.length === 0) {
      return json({ message: "No recipients" });
    }

    const firebaseApp = getFirebaseApp();
    const { data: tokenRows, error } = await adminClient
      .from("fcm_tokens")
      .select("token")
      .in("user_id", payload.userIds);

    if (error) throw error;

    const tokens = [...new Set((tokenRows ?? []).map((row) => row.token).filter(Boolean))];
    if (tokens.length === 0) {
      return json({ message: "No active tokens found" });
    }

    const response = await getMessaging(firebaseApp).sendEachForMulticast({
      tokens,
      notification: { title: payload.title, body: payload.body },
      data: {
        title: payload.title,
        body: payload.body,
        sender_id: payload.senderId,
        chat_id: payload.chatId,
        receiver_id: payload.receiverId,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "high_importance_channel",
          priority: "high",
          sound: "default",
        },
      },
      apns: {
        payload: {
          aps: {
            alert: { title: payload.title, body: payload.body },
            sound: "default",
            badge: 1,
            "content-available": 1,
          },
        },
      },
    });

    return json({
      message: "Notifications dispatched",
      successCount: response.successCount,
      failureCount: response.failureCount,
    });
  } catch (error) {
    console.error("send-notification failed", error);
    return json({ error: "notification_dispatch_failed" }, 500);
  }
});

async function isAuthorizedDispatch(req: Request): Promise<boolean> {
  const suppliedSecret = req.headers.get("x-notification-dispatch-secret") ?? "";
  if (dispatchSecret !== "" && suppliedSecret === dispatchSecret) {
    return true;
  }

  const authorization = req.headers.get("authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (token === "") return false;

  const userClient = createClient(supabaseUrl, serviceRoleKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });

  const { data, error } = await userClient.auth.getUser(token);
  if (error || !data.user) return false;

  const { data: profile, error: profileError } = await adminClient
    .from("profiles")
    .select("role")
    .eq("id", data.user.id)
    .maybeSingle();

  if (profileError) return false;
  return profile?.role === "admin" || profile?.role === "manager";
}

function getFirebaseApp() {
  const apps = getApps();
  if (apps.length > 0) return apps[0];

  if (firebaseServiceAccount === "") {
    throw new Error("FIREBASE_SERVICE_ACCOUNT is not configured");
  }

  const serviceAccount = JSON.parse(firebaseServiceAccount);
  if (typeof serviceAccount.private_key === "string") {
    serviceAccount.private_key = serviceAccount.private_key.replace(/\\n/g, "\n");
  }

  return initializeApp({
    credential: cert(serviceAccount),
  });
}

async function readPayload(req: Request) {
  const body = (await req.json()) as NotificationPayload;
  const userIds = Array.isArray(body.userIds)
    ? body.userIds.filter((id): id is string => typeof id === "string" && isUuid(id))
    : [];

  return {
    userIds,
    title: safeText(body.title, 120),
    body: safeText(body.body, 240),
    senderId: safeText(body.sender_id, 64),
    chatId: safeText(body.chat_id, 64),
    receiverId: safeText(body.receiver_id, 64),
  };
}

function safeText(value: unknown, maxLength: number): string {
  if (typeof value !== "string") return "";
  return value.slice(0, maxLength);
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
