/**
 * Pomopet 친구 연동 서버 (Cloudflare Workers + D1)
 *
 * 앱은 최초 실행 때 /v1/register 로 익명 사용자를 만들고, 받은 secret 을 Keychain 에 보관합니다.
 * 이후 모든 요청은 `Authorization: Bearer <secret>` 로 인증합니다. 이메일·비밀번호·소셜 로그인 없음.
 *
 *   POST   /v1/register        익명 가입 → { userId, code, secret }
 *   GET    /v1/me              내 코드·이름 확인
 *   POST   /v1/heartbeat       내 상태 올리고 친구들 상태 받아오기 (앱이 주기적으로 호출)
 *   POST   /v1/friends         { code } 로 친구 연결 (양방향)
 *   DELETE /v1/friends/:code   친구 끊기 (양방향)
 *   PUT    /v1/pet             내 펫 그림 올리기 (그림이 바뀔 때만)
 *   GET    /v1/pet/:code       친구 펫 그림 받기 (해시가 바뀌었을 때만)
 *   POST   /v1/nudge           { code } 친구 쿡 찌르기
 *   POST   /v1/code/rotate     내 코드 새로 받기 (친구 관계는 유지)
 *   DELETE /v1/me              탈퇴 — 내 흔적 전부 삭제
 *
 * 하루 한 번 휴면 계정을 정리합니다 (cleanupIdleAccounts 참고).
 */

export interface Env {
  DB: D1Database
}

// 헷갈리는 글자(0/O, 1/I/L)를 뺀 31자. 31^6 ≈ 8.9억 가지.
const CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ'
const CODE_LENGTH = 6

const MAX_FRIENDS = 50
const MAX_NAME_LENGTH = 24
const MAX_PET_BASE64 = 24_000 // 26x26 PNG 는 1KB 안팎. 넉넉히 잡아도 이 이상은 거절.
const VALID_PHASES = new Set(['idle', 'focusing', 'breakReady', 'resting'])

const MINUTE = 60_000
const NUDGE_COOLDOWN = 10 * MINUTE // 같은 친구를 다시 찌르기까지
const NUDGE_DAILY_LIMIT = 5 // 같은 친구에게 하루에 보낼 수 있는 횟수
const NUDGE_EXPIRY = 2 * 60 * MINUTE // 이 시간이 지나도록 못 받아간 찌르기는 무시
const NUDGE_RETENTION = 7 * 24 * 60 * MINUTE // 도배 방지 계산용으로만 남겨두는 기간
const NUDGE_INBOX_LIMIT = 20 // 한 번에 받아가는 최대 개수

const DAY = 24 * 60 * MINUTE
const REGISTER_HOURLY_LIMIT = 10 // 같은 IP 에서 한 시간에 만들 수 있는 계정 수

// 없는 코드를 이만큼 찍으면 한 시간 동안 친구 추가를 막습니다.
// 코드가 8.9억 가지라 무작위 대입은 원래 가망이 없지만, 아예 시도조차 못 하게 막아둡니다.
// 실패한 시도만 세므로 정상적으로 쓰는 사람은 걸릴 일이 없습니다(오타 10번까지 허용).
const FRIEND_FAIL_LIMIT = 10
const IP_RETENTION = 1 * DAY // 가입 IP 해시를 이만큼만 들고 있다가 지웁니다

// 휴면 계정 정리 기준. 목적은 용량 절약이 아니라 버려진 계정 청소입니다.
// 연락할 수단이 없어 미리 알릴 수 없으므로, 실제로 쓰는 계정은 최대한 남깁니다.
const IDLE_NEVER_USED = 7 * DAY // 가입만 하고 한 번도 안 켠 계정
const IDLE_NO_FRIENDS = 90 * DAY // 써봤지만 친구가 없는 계정
const IDLE_WITH_FRIENDS = 365 * DAY // 친구가 있는 계정 — 지우면 남의 목록에서 사라지므로 길게
const CLEANUP_BATCH = 500 // 한 번 돌 때 지우는 최대 계정 수

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await route(request, env)
    } catch (err) {
      console.error('unhandled', err)
      return json({ error: 'internal_error' }, 500)
    }
  },

  // 하루 한 번 (wrangler.toml 의 crons) 휴면 계정을 정리합니다.
  async scheduled(_event: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(
      cleanupIdleAccounts(env, Date.now()).then((result) => {
        console.log('cleanup', JSON.stringify(result))
      })
    )
  },
}

// MARK: - 라우팅

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url)
  const path = url.pathname.replace(/\/+$/, '') || '/'
  const method = request.method.toUpperCase()

  if (path === '/' || path === '/v1/health') {
    return json({ ok: true, service: 'pomopet-sync' })
  }

  if (path === '/v1/register' && method === 'POST') return register(request, env)

  // 여기서부터는 인증 필요
  const me = await authenticate(request, env)
  if (!me) return json({ error: 'unauthorized' }, 401)

  if (path === '/v1/me' && method === 'GET') {
    return json({ me: publicUser(me) })
  }
  if (path === '/v1/heartbeat' && method === 'POST') return heartbeat(request, env, me)
  if (path === '/v1/friends' && method === 'POST') return addFriend(request, env, me)
  if (path === '/v1/pet' && method === 'PUT') return putPet(request, env, me)
  if (path === '/v1/nudge' && method === 'POST') return nudge(request, env, me)
  if (path === '/v1/code/rotate' && method === 'POST') return rotateCode(env, me)
  if (path === '/v1/me' && method === 'DELETE') return deleteAccount(env, me)

  const friendMatch = /^\/v1\/friends\/([^/]+)$/.exec(path)
  if (friendMatch && method === 'DELETE') return removeFriend(env, me, friendMatch[1])

  const petMatch = /^\/v1\/pet\/([^/]+)$/.exec(path)
  if (petMatch && method === 'GET') return getPet(env, me, petMatch[1])

  return json({ error: 'not_found' }, 404)
}

// MARK: - 핸들러

async function register(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request)
  const name = cleanName(body?.name)
  const now = Date.now()
  // 원본 IP 는 저장하지 않습니다. 도배를 세는 데는 "같은 곳에서 왔는지"만 알면 충분해서
  // 해시만 남기고, 그마저도 하루 뒤 지웁니다(cleanupIdleAccounts 참고).
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown'
  const ipHash = await hashIP(env, ip)

  // 가입은 인증 없이 열려 있는 유일한 창구라, 같은 곳에서 쏟아붓지 못하게 막습니다.
  const recent = await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM users WHERE signup_ip = ? AND created_at >= ?`
  )
    .bind(ipHash, now - 60 * MINUTE)
    .first<{ n: number }>()
  if ((recent?.n ?? 0) >= REGISTER_HOURLY_LIMIT) {
    return json({ error: 'register_rate_limited', limit: REGISTER_HOURLY_LIMIT }, 429)
  }

  const id = crypto.randomUUID()
  const secret = randomSecret()
  const secretHash = await sha256Hex(secret)

  // 코드가 겹치면 다시 뽑습니다. 8.9억 가지라 실제로는 거의 첫 시도에 성공합니다.
  for (let attempt = 0; attempt < 6; attempt++) {
    const code = randomCode()
    try {
      await env.DB.prepare(
        `INSERT INTO users (id, code, secret_hash, name, signup_ip, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      )
        .bind(id, code, secretHash, name, ipHash, now, now)
        .run()
      return json({ userId: id, code, secret }, 201)
    } catch (err) {
      if (!isUniqueViolation(err)) throw err
    }
  }
  return json({ error: 'code_generation_failed' }, 503)
}

/**
 * 코드를 새로 받습니다. 코드가 엉뚱한 곳에 퍼졌을 때 쓰라고 둔 창구입니다.
 * 친구 관계는 코드가 아니라 내부 id 로 이어져 있어서 그대로 유지됩니다.
 */
async function rotateCode(env: Env, me: UserRow): Promise<Response> {
  for (let attempt = 0; attempt < 6; attempt++) {
    const code = randomCode()
    try {
      await env.DB.prepare(`UPDATE users SET code = ? WHERE id = ?`).bind(code, me.id).run()
      return json({ code })
    } catch (err) {
      if (!isUniqueViolation(err)) throw err
    }
  }
  return json({ error: 'code_generation_failed' }, 503)
}

/** 탈퇴. 내 계정과 친구 관계(양쪽), 주고받은 찌르기까지 전부 지웁니다. */
async function deleteAccount(env: Env, me: UserRow): Promise<Response> {
  await env.DB.batch([
    env.DB.prepare(`DELETE FROM nudges WHERE to_id = ? OR from_id = ?`).bind(me.id, me.id),
    env.DB.prepare(`DELETE FROM friendships WHERE user_id = ? OR friend_id = ?`).bind(me.id, me.id),
    env.DB.prepare(`DELETE FROM users WHERE id = ?`).bind(me.id),
  ])
  return json({ ok: true, deleted: me.code })
}

/**
 * 휴면 계정 정리. 하루 한 번 돕니다.
 *
 * 목적은 용량 절약이 아니라 버려진 계정을 치우는 것입니다. D1 무료 한도는 넉넉하고,
 * 실사용자를 잘못 지우면 그 사람은 친구를 전부 다시 추가해야 하는 데다 미리 알릴 방법도 없습니다.
 * 그래서 버려진 게 확실한 것부터 짧게, 실제로 쓰이는 것일수록 길게 잡았습니다.
 */
export async function cleanupIdleAccounts(env: Env, now: number) {
  const candidates = await env.DB.prepare(
    `SELECT u.id, u.created_at, u.updated_at,
            (SELECT COUNT(*) FROM friendships f WHERE f.user_id = u.id) AS friend_count
       FROM users u
      WHERE u.updated_at < ?
         OR (u.updated_at = u.created_at AND u.created_at < ?)
      LIMIT ?`
  )
    .bind(now - IDLE_NO_FRIENDS, now - IDLE_NEVER_USED, CLEANUP_BATCH)
    .all<{ id: string; created_at: number; updated_at: number; friend_count: number }>()

  // 오래된 가입 IP 해시를 지웁니다. 도배를 세는 창은 한 시간이라 하루면 충분히 넉넉합니다.
  await env.DB.prepare(`UPDATE users SET signup_ip = NULL WHERE signup_ip IS NOT NULL AND created_at < ?`)
    .bind(now - IP_RETENTION)
    .run()

  const doomed = (candidates.results ?? []).filter((u) => {
    const idleFor = now - u.updated_at
    if (u.friend_count > 0) return idleFor > IDLE_WITH_FRIENDS
    if (u.updated_at === u.created_at) return now - u.created_at > IDLE_NEVER_USED
    return idleFor > IDLE_NO_FRIENDS
  })

  if (doomed.length === 0) {
    return { scanned: candidates.results?.length ?? 0, deleted: 0 }
  }

  const ids = doomed.map((u) => u.id)
  const placeholders = ids.map(() => '?').join(',')
  await env.DB.batch([
    env.DB.prepare(
      `DELETE FROM nudges WHERE to_id IN (${placeholders}) OR from_id IN (${placeholders})`
    ).bind(...ids, ...ids),
    env.DB.prepare(
      `DELETE FROM friendships WHERE user_id IN (${placeholders}) OR friend_id IN (${placeholders})`
    ).bind(...ids, ...ids),
    env.DB.prepare(`DELETE FROM users WHERE id IN (${placeholders})`).bind(...ids),
  ])

  return { scanned: candidates.results?.length ?? 0, deleted: ids.length }
}

async function heartbeat(request: Request, env: Env, me: UserRow): Promise<Response> {
  const body = await readJson(request)
  if (!body) return json({ error: 'invalid_body' }, 400)

  const name = cleanName(body.name ?? me.name)
  const dayKey = clampInt(body.dayKey, 0, 99991231, me.day_key)
  const sessions = clampInt(body.sessions, 0, 200, 0)
  const minutes = clampInt(body.minutes, 0, 1440, 0)
  const goal = clampInt(body.goal, 1, 20, 1)
  const streak = clampInt(body.streak, 0, 100000, 0)
  const activated = body.activated ? 1 : 0
  const phase = VALID_PHASES.has(body.phase) ? body.phase : 'idle'
  const now = Date.now()

  await env.DB.prepare(
    `UPDATE users
        SET name = ?, day_key = ?, sessions = ?, minutes = ?, goal = ?,
            activated = ?, streak = ?, phase = ?, updated_at = ?
      WHERE id = ?`
  )
    .bind(name, dayKey, sessions, minutes, goal, activated, streak, phase, now, me.id)
    .run()

  const friends = await listFriends(env, me.id)
  const nudges = await collectNudges(env, me.id, now)
  return json({
    me: { ...publicUser(me), name, dayKey, sessions, minutes, goal, activated: !!activated, streak, phase },
    friends,
    nudges,
    serverTime: now,
  })
}

/** 나를 찌른 기록을 받아가고, 받아간 것으로 표시합니다. 같은 찌르기를 두 번 보여주지 않기 위함입니다. */
async function collectNudges(env: Env, userId: string, now: number) {
  const cutoff = now - NUDGE_EXPIRY
  const result = await env.DB.prepare(
    `SELECT n.id, u.code AS from_code, u.name AS from_name, n.created_at
       FROM nudges n
       JOIN users u ON u.id = n.from_id
      WHERE n.to_id = ? AND n.delivered_at IS NULL AND n.created_at >= ?
      ORDER BY n.created_at ASC
      LIMIT ?`
  )
    .bind(userId, cutoff, NUDGE_INBOX_LIMIT)
    .all<{ id: string; from_code: string; from_name: string; created_at: number }>()

  const rows = result.results ?? []
  if (rows.length === 0) return []

  const placeholders = rows.map(() => '?').join(',')
  await env.DB.prepare(`UPDATE nudges SET delivered_at = ? WHERE id IN (${placeholders})`)
    .bind(now, ...rows.map((r) => r.id))
    .run()

  return rows.map((r) => ({ from: r.from_code, name: r.from_name, at: r.created_at }))
}

async function nudge(request: Request, env: Env, me: UserRow): Promise<Response> {
  const body = await readJson(request)
  const code = normalizeCode(body?.code)
  if (!code) return json({ error: 'invalid_code' }, 400)
  if (code === me.code) return json({ error: 'cannot_nudge_self' }, 400)

  // 친구인 사람만 찌를 수 있습니다.
  const target = await env.DB.prepare(
    `SELECT u.id, u.code
       FROM users u
       JOIN friendships f ON f.friend_id = u.id AND f.user_id = ?
      WHERE u.code = ?`
  )
    .bind(me.id, code)
    .first<{ id: string; code: string }>()
  if (!target) return json({ error: 'not_a_friend' }, 403)

  const now = Date.now()
  const recent = await env.DB.prepare(
    `SELECT MAX(created_at) AS last_at,
            SUM(CASE WHEN created_at >= ? THEN 1 ELSE 0 END) AS today_count
       FROM nudges
      WHERE from_id = ? AND to_id = ?`
  )
    .bind(now - 24 * 60 * MINUTE, me.id, target.id)
    .first<{ last_at: number | null; today_count: number | null }>()

  const lastAt = recent?.last_at ?? 0
  if (lastAt && now - lastAt < NUDGE_COOLDOWN) {
    return json({ error: 'nudge_too_soon', retryAfterMs: NUDGE_COOLDOWN - (now - lastAt) }, 429)
  }
  if ((recent?.today_count ?? 0) >= NUDGE_DAILY_LIMIT) {
    return json({ error: 'nudge_daily_limit', limit: NUDGE_DAILY_LIMIT }, 429)
  }

  await env.DB.prepare(
    `INSERT INTO nudges (id, to_id, from_id, created_at) VALUES (?, ?, ?, ?)`
  )
    .bind(crypto.randomUUID(), target.id, me.id, now)
    .run()

  // 오래된 기록은 여기서 같이 치웁니다. 따로 청소 작업을 돌릴 필요가 없습니다.
  await env.DB.prepare(`DELETE FROM nudges WHERE from_id = ? AND created_at < ?`)
    .bind(me.id, now - NUDGE_RETENTION)
    .run()

  return json({ ok: true, to: target.code, at: now }, 201)
}

async function addFriend(request: Request, env: Env, me: UserRow): Promise<Response> {
  const body = await readJson(request)
  const code = normalizeCode(body?.code)
  if (!code) return json({ error: 'invalid_code' }, 400)
  if (code === me.code) return json({ error: 'cannot_add_self' }, 400)

  // 없는 코드를 계속 찍는 건 코드를 훑는 행위입니다. 한 시간에 몇 번까지만 허용합니다.
  const now = Date.now()
  const fails = now - me.friend_fail_at < 60 * MINUTE ? me.friend_fails : 0
  if (fails >= FRIEND_FAIL_LIMIT) {
    return json({ error: 'too_many_attempts' }, 429)
  }

  const target = await env.DB.prepare(`SELECT * FROM users WHERE code = ?`)
    .bind(code)
    .first<UserRow>()
  if (!target) {
    await env.DB.prepare(`UPDATE users SET friend_fails = ?, friend_fail_at = ? WHERE id = ?`)
      .bind(fails + 1, now, me.id)
      .run()
    return json({ error: 'code_not_found' }, 404)
  }

  const countRow = await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM friendships WHERE user_id = ?`
  )
    .bind(me.id)
    .first<{ n: number }>()
  if ((countRow?.n ?? 0) >= MAX_FRIENDS) return json({ error: 'friend_limit_reached' }, 409)

  const insert = `INSERT OR IGNORE INTO friendships (user_id, friend_id, created_at) VALUES (?, ?, ?)`
  await env.DB.batch([
    env.DB.prepare(insert).bind(me.id, target.id, now),
    env.DB.prepare(insert).bind(target.id, me.id, now),
  ])

  return json({ friend: publicUser(target) }, 201)
}

async function removeFriend(env: Env, me: UserRow, rawCode: string): Promise<Response> {
  const code = normalizeCode(rawCode)
  if (!code) return json({ error: 'invalid_code' }, 400)

  const target = await env.DB.prepare(`SELECT id FROM users WHERE code = ?`)
    .bind(code)
    .first<{ id: string }>()
  if (!target) return json({ error: 'code_not_found' }, 404)

  const del = `DELETE FROM friendships WHERE user_id = ? AND friend_id = ?`
  await env.DB.batch([
    env.DB.prepare(del).bind(me.id, target.id),
    env.DB.prepare(del).bind(target.id, me.id),
  ])
  return json({ ok: true })
}

async function putPet(request: Request, env: Env, me: UserRow): Promise<Response> {
  const body = await readJson(request)
  const pet = typeof body?.pet === 'string' ? body.pet : null
  const petHash = typeof body?.petHash === 'string' ? body.petHash.slice(0, 64) : null
  if (!pet || !petHash) return json({ error: 'invalid_body' }, 400)
  if (pet.length > MAX_PET_BASE64) return json({ error: 'pet_too_large' }, 413)
  if (!/^[A-Za-z0-9+/=]+$/.test(pet)) return json({ error: 'pet_not_base64' }, 400)

  await env.DB.prepare(`UPDATE users SET pet = ?, pet_hash = ?, updated_at = ? WHERE id = ?`)
    .bind(pet, petHash, Date.now(), me.id)
    .run()
  return json({ ok: true, petHash })
}

async function getPet(env: Env, me: UserRow, rawCode: string): Promise<Response> {
  const code = normalizeCode(rawCode)
  if (!code) return json({ error: 'invalid_code' }, 400)

  // 내 펫이거나, 내 친구의 펫만 볼 수 있습니다.
  const row = await env.DB.prepare(
    `SELECT u.code, u.pet, u.pet_hash
       FROM users u
      WHERE u.code = ?
        AND (u.id = ? OR EXISTS (
              SELECT 1 FROM friendships f WHERE f.user_id = ? AND f.friend_id = u.id))`
  )
    .bind(code, me.id, me.id)
    .first<{ code: string; pet: string | null; pet_hash: string | null }>()

  if (!row) return json({ error: 'not_found' }, 404)
  if (!row.pet) return json({ error: 'no_pet' }, 404)
  return json({ code: row.code, petHash: row.pet_hash, pet: row.pet })
}

async function listFriends(env: Env, userId: string) {
  const result = await env.DB.prepare(
    `SELECT u.code, u.name, u.day_key, u.sessions, u.minutes, u.goal,
            u.activated, u.streak, u.phase, u.pet_hash, u.updated_at
       FROM friendships f
       JOIN users u ON u.id = f.friend_id
      WHERE f.user_id = ?
      ORDER BY f.created_at ASC`
  )
    .bind(userId)
    .all<UserRow>()
  return (result.results ?? []).map(publicUser)
}

// MARK: - 인증

async function authenticate(request: Request, env: Env): Promise<UserRow | null> {
  const header = request.headers.get('Authorization') ?? ''
  if (!header.startsWith('Bearer ')) return null
  const secret = header.slice(7).trim()
  if (!secret) return null

  // 원본이 아니라 해시로 조회합니다 — 서버가 털려도 secret 자체는 남지 않습니다.
  const hash = await sha256Hex(secret)
  return await env.DB.prepare(`SELECT * FROM users WHERE secret_hash = ?`)
    .bind(hash)
    .first<UserRow>()
}

// MARK: - 유틸

interface UserRow {
  id: string
  code: string
  name: string
  day_key: number
  sessions: number
  minutes: number
  goal: number
  activated: number
  streak: number
  phase: string
  pet_hash: string | null
  updated_at: number
  friend_fails: number
  friend_fail_at: number
}

// Swift Codable 쪽에서 그대로 받도록 camelCase 로 내보냅니다. secret·id 는 절대 포함하지 않습니다.
function publicUser(row: UserRow) {
  return {
    code: row.code,
    name: row.name,
    dayKey: row.day_key,
    sessions: row.sessions,
    minutes: row.minutes,
    goal: row.goal,
    activated: !!row.activated,
    streak: row.streak,
    phase: row.phase,
    petHash: row.pet_hash,
    updatedAt: row.updated_at,
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  })
}

async function readJson(request: Request): Promise<any> {
  try {
    return await request.json()
  } catch {
    return null
  }
}

function cleanName(value: unknown): string {
  if (typeof value !== 'string') return ''
  return value.replace(/\s+/g, ' ').trim().slice(0, MAX_NAME_LENGTH)
}

function clampInt(value: unknown, min: number, max: number, fallback: number): number {
  const n = typeof value === 'number' ? Math.floor(value) : Number.NaN
  if (!Number.isFinite(n)) return fallback
  return Math.min(max, Math.max(min, n))
}

/** 사용자가 소문자로 치거나 하이픈을 넣어도 받아줍니다: "7k3-qm2" → "7K3QM2" */
function normalizeCode(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const code = value.toUpperCase().replace(/[^A-Z0-9]/g, '')
  if (code.length !== CODE_LENGTH) return null
  for (const ch of code) if (!CODE_ALPHABET.includes(ch)) return null
  return code
}

function randomCode(): string {
  const bytes = new Uint8Array(CODE_LENGTH)
  crypto.getRandomValues(bytes)
  let out = ''
  for (const b of bytes) out += CODE_ALPHABET[b % CODE_ALPHABET.length]
  return out
}

function randomSecret(): string {
  const bytes = new Uint8Array(32)
  crypto.getRandomValues(bytes)
  let binary = ''
  for (const b of bytes) binary += String.fromCharCode(b)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

/**
 * IP 를 그대로 두지 않고 해시로 바꿉니다.
 *
 * 서버 코드가 공개되어 있으므로 고정된 소금을 코드에 박으면 의미가 없습니다.
 * 대신 첫 가입 때 무작위 소금을 만들어 이 DB 안에만 둡니다 — 직접 띄운 서버마다 값이 다르고,
 * DB 가 새더라도 소금 없이는 해시에서 IP 를 되짚을 수 없습니다.
 */
async function hashIP(env: Env, ip: string): Promise<string> {
  let salt = (
    await env.DB.prepare(`SELECT value FROM meta WHERE key = 'ip_salt'`).first<{ value: string }>()
  )?.value

  if (!salt) {
    salt = randomSecret()
    await env.DB.prepare(`INSERT OR IGNORE INTO meta (key, value) VALUES ('ip_salt', ?)`)
      .bind(salt)
      .run()
    salt =
      (await env.DB.prepare(`SELECT value FROM meta WHERE key = 'ip_salt'`).first<{ value: string }>())
        ?.value ?? salt
  }

  return (await sha256Hex(`${salt}:${ip}`)).slice(0, 32)
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input))
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

function isUniqueViolation(err: unknown): boolean {
  return err instanceof Error && /UNIQUE constraint failed/i.test(err.message)
}
