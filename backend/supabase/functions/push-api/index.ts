import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-admin-code",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("PRIVATE_SERVICE_ROLE_KEY") ?? "";
const adminCodeHash = Deno.env.get("ADMIN_CODE_HASH") ?? "";
const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY") ?? "";
const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
const vapidContactEmail = Deno.env.get("VAPID_CONTACT_EMAIL") ?? "admin@example.com";

if (!supabaseUrl || !serviceRoleKey) {
  console.warn("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is missing.");
}

if (!vapidPublicKey || !vapidPrivateKey) {
  console.warn("VAPID keys are missing.");
}

const supabase = createClient(supabaseUrl, serviceRoleKey);
webpush.setVapidDetails(`mailto:${vapidContactEmail}`, vapidPublicKey, vapidPrivateKey);

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json"
    }
  });
}

async function sha256(value: string) {
  const buffer = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(buffer))
    .map((part) => part.toString(16).padStart(2, "0"))
    .join("");
}

function getAction(pathname: string) {
  const segments = pathname.split("/").filter(Boolean);
  const last = segments.at(-1) ?? "";
  return last === "push-api" ? "" : last;
}

function ensureSubscription(body: any) {
  const subscription = body?.subscription;

  if (!subscription?.endpoint || !subscription?.keys?.p256dh || !subscription?.keys?.auth) {
    throw new Error("Missing subscription payload.");
  }

  return subscription;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const action = getAction(new URL(request.url).pathname);

  try {
    if (action === "subscribe") {
      const body = await request.json();
      const subscription = ensureSubscription(body);

      const { error } = await supabase.from("push_subscriptions").upsert({
        endpoint: subscription.endpoint,
        subscription,
        site: body.site ?? null,
        page: body.page ?? null,
        user_agent: body.userAgent ?? null,
        updated_at: new Date().toISOString(),
        last_seen_at: new Date().toISOString()
      }, {
        onConflict: "endpoint"
      });

      if (error) {
        throw error;
      }

      return jsonResponse({ ok: true });
    }

    if (action === "unsubscribe") {
      const body = await request.json();

      if (!body?.endpoint) {
        return jsonResponse({ error: "Missing endpoint." }, 400);
      }

      const { error } = await supabase
        .from("push_subscriptions")
        .delete()
        .eq("endpoint", body.endpoint);

      if (error) {
        throw error;
      }

      return jsonResponse({ ok: true });
    }

    if (action === "send") {
      const body = await request.json();
      const incomingCode = (request.headers.get("x-admin-code") ?? "").trim();

      if (!incomingCode) {
        return jsonResponse({ error: "Missing admin code." }, 401);
      }

      const incomingHash = await sha256(incomingCode);

      if (!adminCodeHash || incomingHash !== adminCodeHash) {
        return jsonResponse({ error: "Invalid admin code." }, 403);
      }

      const title = String(body?.title ?? "").trim();
      const messageBody = String(body?.body ?? "").trim();
      const url = String(body?.url ?? "").trim();

      if (!title || !messageBody || !url) {
        return jsonResponse({ error: "Title, body and url are required." }, 400);
      }

      const insertResult = await supabase
        .from("internal_messages")
        .insert({
          title,
          body: messageBody,
          url
        })
        .select("id, title, body, url, created_at")
        .single();

      if (insertResult.error || !insertResult.data) {
        throw insertResult.error ?? new Error("Message insert failed.");
      }

      const message = insertResult.data;

      const subscriptionsResult = await supabase
        .from("push_subscriptions")
        .select("endpoint, subscription");

      if (subscriptionsResult.error) {
        throw subscriptionsResult.error;
      }

      const staleEndpoints: string[] = [];
      const sendResults = await Promise.all(
        (subscriptionsResult.data ?? []).map(async (record) => {
          try {
            await webpush.sendNotification(record.subscription as any, JSON.stringify({
              id: `msg-${message.id}`,
              title: message.title,
              body: message.body,
              url: message.url,
              sentAt: message.created_at,
              source: "admin"
            }));

            return true;
          } catch (error: any) {
            const statusCode = error?.statusCode ?? error?.status ?? 0;

            if (statusCode === 404 || statusCode === 410) {
              staleEndpoints.push(record.endpoint);
            } else {
              console.error("Push send failed", error);
            }

            return false;
          }
        })
      );

      const sentCount = sendResults.filter(Boolean).length;

      if (staleEndpoints.length) {
        await supabase
          .from("push_subscriptions")
          .delete()
          .in("endpoint", staleEndpoints);
      }

      return jsonResponse({
        ok: true,
        sentCount,
        staleRemoved: staleEndpoints.length,
        messageId: message.id
      });
    }

    return jsonResponse({ error: "Unknown action." }, 404);
  } catch (error) {
    console.error(error);
    return jsonResponse({ error: "Server error." }, 500);
  }
});
