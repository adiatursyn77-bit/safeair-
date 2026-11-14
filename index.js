// ====== Gas Leak Tracker — Cloudflare Worker backend ======
// Заменяет Firebase Cloud Functions (которые требуют платный план Blaze).
// Работает полностью на бесплатном тарифе Cloudflare Workers.
//
// Обращается к Firestore и Firebase Cloud Messaging напрямую через их
// REST API, аутентифицируясь как сервисный аккаунт Google Cloud
// (тот же механизм, что использует Admin SDK — то есть эти запросы
// ПОЛНОСТЬЮ ОБХОДЯТ Firestore Security Rules, они предназначены только
// для клиентского SDK в Flutter-приложении).

// ====== Вспомогательные функции: base64url ======

function base64UrlEncode(data) {
  let base64;
  if (typeof data === "string") {
    base64 = btoa(data);
  } else {
    const bytes = new Uint8Array(data);
    let binary = "";
    for (let i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    base64 = btoa(binary);
  }
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// ====== Вспомогательные функции: PEM -> ArrayBuffer (для приватного ключа) ======

function pemToArrayBuffer(pem) {
  // Оставляем ТОЛЬКО валидные base64-символы. Это устойчиво к любому
  // мусору, который мог попасть при копировании ключа — лишним кавычкам
  // от JSON, запятым в конце строки, \r от Windows-переносов и т.п.
  // Раньше здесь удалялись только пробелы, и любой такой "мусорный"
  // символ ломал atob() с ошибкой "invalid base64-encoded data".
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/[^A-Za-z0-9+/=]/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

// ====== SHA-256 хэш секрета (совпадает с тем, что считает Flutter-приложение) ======

async function sha256Hex(text) {
  const encoder = new TextEncoder();
  const data = encoder.encode(text);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ====== Получение OAuth2 access token сервисного аккаунта ======
// Кэшируется в памяти воркера между запросами (в рамках одного isolate),
// чтобы не подписывать новый JWT на каждый вызов.

let cachedToken = null;
let cachedTokenExpiry = 0;

async function getAccessToken(env) {
  const now = Math.floor(Date.now() / 1000);

  if (cachedToken && now < cachedTokenExpiry - 60) {
    return cachedToken;
  }

  const header = { alg: "RS256", typ: "JWT" };
  const scope =
    "https://www.googleapis.com/auth/datastore " +
    "https://www.googleapis.com/auth/firebase.messaging";

  // Убираем случайные пробелы/переносы строк по краям — частый артефакт
  // при вставке значения в интерактивный prompt терминала. Google строго
  // сверяет email сервисного аккаунта, лишний \n/пробел даёт ошибку
  // "invalid_grant: account not found", хотя сам ключ подписан корректно.
  const claimSet = {
    iss: env.GCP_SERVICE_ACCOUNT_EMAIL.trim(),
    scope,
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedClaimSet = base64UrlEncode(JSON.stringify(claimSet));
  const signingInput = `${encodedHeader}.${encodedClaimSet}`;

  const privateKeyPem = env.GCP_SERVICE_ACCOUNT_PRIVATE_KEY.replace(/\\n/g, "\n");
  const keyData = pemToArrayBuffer(privateKeyPem);

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signatureBuffer = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput)
  );

  const encodedSignature = base64UrlEncode(signatureBuffer);
  const jwt = `${signingInput}.${encodedSignature}`;

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body:
      "grant_type=" +
      encodeURIComponent("urn:ietf:params:oauth:grant-type:jwt-bearer") +
      "&assertion=" +
      encodeURIComponent(jwt),
  });

  if (!tokenResponse.ok) {
    const errText = await tokenResponse.text();
    throw new Error("Не удалось получить access token: " + errText);
  }

  const tokenJson = await tokenResponse.json();
  cachedToken = tokenJson.access_token;
  cachedTokenExpiry = now + tokenJson.expires_in;
  return cachedToken;
}

// ====== Firestore REST helpers ======
// Firestore REST API представляет значения в "типизированном" виде:
// {"stringValue": "..."}, {"integerValue": "..."}, {"timestampValue": "..."},
// {"nullValue": null}, {"arrayValue": {"values": [...]}}.
// Ниже — минимальный набор хелперов под наши нужды.

function firestoreBaseUrl(env) {
  return `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents`;
}

async function firestoreGetDoc(env, token, path) {
  const res = await fetch(`${firestoreBaseUrl(env)}/${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 404) return null;
  if (!res.ok) {
    throw new Error(`Firestore GET ${path} failed: ${await res.text()}`);
  }
  return res.json();
}

async function firestorePatchDoc(env, token, path, fields, updateMaskFields) {
  const maskQuery = updateMaskFields
    .map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`)
    .join("&");
  const res = await fetch(`${firestoreBaseUrl(env)}/${path}?${maskQuery}`, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) {
    throw new Error(`Firestore PATCH ${path} failed: ${await res.text()}`);
  }
  return res.json();
}

async function firestoreCreateDoc(env, token, collectionPath, fields) {
  const res = await fetch(`${firestoreBaseUrl(env)}/${collectionPath}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) {
    throw new Error(`Firestore CREATE ${collectionPath} failed: ${await res.text()}`);
  }
  const json = await res.json();
  // json.name выглядит как ".../documents/devices/xxx/events/AUTO_ID"
  const parts = json.name.split("/");
  const id = parts[parts.length - 1];
  return { id, doc: json };
}

function getStringField(doc, fieldName) {
  return doc?.fields?.[fieldName]?.stringValue ?? null;
}

function getArrayField(doc, fieldName) {
  const values = doc?.fields?.[fieldName]?.arrayValue?.values ?? [];
  return values.map((v) => v.stringValue).filter(Boolean);
}

// ====== Отправка push-уведомления через FCM HTTP v1 ======

async function sendFcmToToken(env, token, deviceToken, title, body) {
  const url = `https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: {
        token: deviceToken,
        notification: { title, body },
        android: {
          priority: "high",
          notification: {
            channel_id: "gas_leak_alerts_v2",
            notification_priority: "PRIORITY_MAX",
            default_vibrate_timings: true,
            default_sound: true,
          },
        },
      },
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    // Временная диагностика — смотрим в `wrangler tail`, что именно
    // отвечает FCM, когда res.ok == false.
    console.log(
      `[fcm] ОШИБКА отправки на токен ...${deviceToken.slice(-12)}: ` +
        `HTTP ${res.status} ${errText}`
    );
    let status;
    try {
      status = JSON.parse(errText)?.error?.status;
    } catch (_) {
      status = undefined;
    }
    const isInvalidToken =
      status === "UNREGISTERED" || status === "INVALID_ARGUMENT";
    return { ok: false, invalidToken: isInvalidToken };
  }

  const resJson = await res.json().catch(() => null);
  console.log(
    `[fcm] Успешно отправлено на токен ...${deviceToken.slice(-12)}: ` +
      `${JSON.stringify(resJson)}`
  );

  return { ok: true, invalidToken: false };
}

async function notifyOwner(env, accessToken, memberUids, title, body) {
  console.log(`[fcm] notifyOwner вызван для memberUids: ${JSON.stringify(memberUids)}`);

  // Шлём push каждому участнику платы отдельно — у каждого свой набор
  // fcmTokens в его собственном документе users/{uid}.
  for (const uid of memberUids) {
    const userDoc = await firestoreGetDoc(env, accessToken, `users/${uid}`);
    if (!userDoc) {
      console.log(`[fcm] Документ users/${uid} не найден — пропускаем`);
      continue;
    }

    const tokens = getArrayField(userDoc, "fcmTokens");
    console.log(`[fcm] users/${uid} — найдено токенов: ${tokens.length}`);
    if (tokens.length === 0) continue;

    const invalidTokens = [];

    for (const t of tokens) {
      const result = await sendFcmToToken(env, accessToken, t, title, body);
      if (!result.ok && result.invalidToken) {
        invalidTokens.push(t);
      }
    }

    if (invalidTokens.length > 0) {
      const remainingTokens = tokens.filter((t) => !invalidTokens.includes(t));
      await firestorePatchDoc(
        env,
        accessToken,
        `users/${uid}`,
        {
          fcmTokens: {
            arrayValue: {
              values: remainingTokens.map((t) => ({ stringValue: t })),
            },
          },
        },
        ["fcmTokens"]
      );
    }
  }
}

// ====== Проверка устройства (deviceId + secret) ======

function isValidDeviceId(deviceId) {
  return typeof deviceId === "string" && /^[a-zA-Z0-9_-]{4,64}$/.test(deviceId);
}

async function verifyDevice(env, accessToken, deviceId, secret) {
  if (!isValidDeviceId(deviceId)) {
    throw new Error("invalid deviceId");
  }
  if (typeof secret !== "string" || secret.length < 8) {
    throw new Error("invalid secret");
  }

  const deviceDoc = await firestoreGetDoc(env, accessToken, `devices/${deviceId}`);
  if (!deviceDoc) {
    throw new Error("device not found");
  }

  const expectedHash = getStringField(deviceDoc, "secretHash");
  const actualHash = await sha256Hex(secret);

  if (!expectedHash || actualHash !== expectedHash) {
    throw new Error("secret mismatch");
  }

  return deviceDoc;
}

// ====== HTTP-обработчики ======

async function handleHeartbeat(request, env) {
  const body = await request.json().catch(() => ({}));
  const accessToken = await getAccessToken(env);

  try {
    await verifyDevice(env, accessToken, body.deviceId, body.secret);
  } catch (err) {
    return jsonResponse({ ok: false, error: err.message }, 403);
  }

  const fields = { lastSeenAt: { timestampValue: new Date().toISOString() } };
  const mask = ["lastSeenAt"];

  // Последние показания датчиков (необязательные поля от платы)
  if (typeof body.gas === "number" && isFinite(body.gas)) {
    fields.lastGas = { doubleValue: body.gas };
    mask.push("lastGas");
  }
  if (typeof body.temp === "number" && isFinite(body.temp)) {
    fields.lastTemp = { doubleValue: body.temp };
    mask.push("lastTemp");
  }
  if (typeof body.hum === "number" && isFinite(body.hum)) {
    fields.lastHum = { doubleValue: body.hum };
    mask.push("lastHum");
  }

  await firestorePatchDoc(
    env,
    accessToken,
    `devices/${body.deviceId}`,
    fields,
    mask
  );

  return jsonResponse({ ok: true });
}

async function handleGasEvent(request, env) {
  const body = await request.json().catch(() => ({}));
  const accessToken = await getAccessToken(env);

  let deviceDoc;
  try {
    deviceDoc = await verifyDevice(env, accessToken, body.deviceId, body.secret);
  } catch (err) {
    return jsonResponse({ ok: false, error: err.message }, 403);
  }

  const deviceId = body.deviceId;
  const memberUids = getArrayField(deviceDoc, "memberUids");
  const deviceName = getStringField(deviceDoc, "name") ?? deviceId;

  if (body.type === "leak_start") {
    const nowIso = new Date().toISOString();

    const { id: eventId } = await firestoreCreateDoc(
      env,
      accessToken,
      `devices/${deviceId}/events`,
      {
        type: { stringValue: "leak_start" },
        startedAt: { timestampValue: nowIso },
        endedAt: { nullValue: null },
        durationSec: { nullValue: null },
      }
    );

    await firestorePatchDoc(
      env,
      accessToken,
      `devices/${deviceId}`,
      {
        status: { stringValue: "alarm" },
        activeEventId: { stringValue: eventId },
      },
      ["status", "activeEventId"]
    );

    if (memberUids.length > 0) {
      await notifyOwner(
        env,
        accessToken,
        memberUids,
        "🚨 Утечка газа!",
        `Устройство "${deviceName}" зафиксировало утечку газа.`
      );
    }

    return jsonResponse({ ok: true, eventId });
  }

  if (body.type === "leak_end") {
    const activeEventId = getStringField(deviceDoc, "activeEventId");
    if (!activeEventId) {
      return jsonResponse({ ok: false, error: "no active event" }, 409);
    }

    const durationSec =
      typeof body.durationSec === "number" ? body.durationSec : null;
    const nowIso = new Date().toISOString();

    const eventFields = {
      type: { stringValue: "leak_end" },
      endedAt: { timestampValue: nowIso },
    };
    const eventMask = ["type", "endedAt"];

    if (durationSec !== null) {
      eventFields.durationSec = { integerValue: String(durationSec) };
      eventMask.push("durationSec");
    }

    await firestorePatchDoc(
      env,
      accessToken,
      `devices/${deviceId}/events/${activeEventId}`,
      eventFields,
      eventMask
    );

    // Убираем activeEventId: в PATCH-запросе поле указывается в updateMask,
    // но НЕ включается в fields — так Firestore REST API удаляет поле.
    await firestorePatchDoc(
      env,
      accessToken,
      `devices/${deviceId}`,
      { status: { stringValue: "ok" } },
      ["status", "activeEventId"]
    );

    if (memberUids.length > 0) {
      await notifyOwner(
        env,
        accessToken,
        memberUids,
        "✅ Утечка устранена",
        `Устройство "${deviceName}" сообщает: газ больше не обнаружен.`
      );
    }

    return jsonResponse({ ok: true });
  }

  return jsonResponse({ ok: false, error: "unknown event type" }, 400);
}

function jsonResponse(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// ====== Роутинг ======

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return jsonResponse({ ok: false, error: "method not allowed" }, 405);
    }

    const url = new URL(request.url);

    try {
      if (url.pathname === "/heartbeat") {
        return await handleHeartbeat(request, env);
      }
      if (url.pathname === "/gasEvent") {
        return await handleGasEvent(request, env);
      }
      return jsonResponse({ ok: false, error: "not found" }, 404);
    } catch (err) {
      return jsonResponse({ ok: false, error: err.message }, 500);
    }
  },
};
