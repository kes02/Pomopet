#!/usr/bin/env node
/**
 * 친구 연동 서버 통합 테스트.
 * 별도 의존성 없이 두 사용자를 만들어 실제 흐름(가입 → 코드로 연결 → 상태 교환 → 펫 전송 → 끊기)을 확인합니다.
 *
 *   1) 터미널 A: npm run dev
 *   2) 터미널 B: npm test
 */

const BASE = process.env.POMOPET_SYNC_URL ?? 'http://127.0.0.1:8787'
const isLocal = /^https?:\/\/(127\.0\.0\.1|localhost)/.test(BASE)

let passed = 0
let failed = 0

function check(label, condition, detail) {
  if (condition) {
    passed++
    console.log(`  ok   ${label}`)
  } else {
    failed++
    console.log(`  FAIL ${label}${detail ? ` — ${detail}` : ''}`)
  }
}

async function call(method, path, { secret, body } = {}) {
  const headers = {}
  if (secret) headers.Authorization = `Bearer ${secret}`
  if (body !== undefined) headers['content-type'] = 'application/json'
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  let json = null
  try {
    json = await res.json()
  } catch {
    /* 본문이 없을 수 있음 */
  }
  return { status: res.status, body: json }
}

const status = (dayKey, sessions, activated, streak, phase = 'idle') => ({
  name: undefined,
  dayKey,
  sessions,
  minutes: sessions * 25,
  goal: 3,
  activated,
  streak,
  phase,
})

async function main() {
  console.log(`\n대상 서버: ${BASE}\n`)

  // --- 기본 확인 -------------------------------------------------------
  console.log('health')
  const health = await call('GET', '/')
  check('서버가 살아있다', health.status === 200 && health.body?.ok === true, JSON.stringify(health.body))

  // --- 가입 ------------------------------------------------------------
  console.log('\nregister')
  const a = (await call('POST', '/v1/register', { body: { name: '경석' } })).body
  const b = (await call('POST', '/v1/register', { body: { name: '친구' } })).body
  check('A 가입 — 6자리 코드 발급', /^[2-9A-HJ-NP-Z]{6}$/.test(a?.code ?? ''), a?.code)
  check('B 가입 — 6자리 코드 발급', /^[2-9A-HJ-NP-Z]{6}$/.test(b?.code ?? ''), b?.code)
  check('두 사람의 코드가 다르다', a?.code !== b?.code)
  check('secret 이 내려온다', typeof a?.secret === 'string' && a.secret.length > 20)

  // --- 인증 ------------------------------------------------------------
  console.log('\nauth')
  const noAuth = await call('POST', '/v1/heartbeat', { body: status(20260730, 1, false, 1) })
  check('토큰 없으면 401', noAuth.status === 401)
  const badAuth = await call('GET', '/v1/me', { secret: 'not-a-real-secret' })
  check('엉뚱한 토큰이면 401', badAuth.status === 401)
  const me = await call('GET', '/v1/me', { secret: a.secret })
  check('내 정보 조회', me.status === 200 && me.body?.me?.code === a.code)
  check('응답에 secret 이 새지 않는다', !JSON.stringify(me.body).includes(a.secret))

  // --- 친구 연결 -------------------------------------------------------
  console.log('\nfriends')
  const self = await call('POST', '/v1/friends', { secret: a.secret, body: { code: a.code } })
  check('내 코드는 추가할 수 없다', self.status === 400 && self.body?.error === 'cannot_add_self')

  const ghost = await call('POST', '/v1/friends', { secret: a.secret, body: { code: 'ZZZZZZ' } })
  check('없는 코드는 404', ghost.status === 404)

  const short = await call('POST', '/v1/friends', { secret: a.secret, body: { code: '123' } })
  check('형식이 틀리면 400', short.status === 400)

  // 소문자·하이픈으로 입력해도 받아줘야 합니다.
  const messy = b.code.toLowerCase().slice(0, 3) + '-' + b.code.toLowerCase().slice(3)
  const added = await call('POST', '/v1/friends', { secret: a.secret, body: { code: messy } })
  check(`소문자·하이픈 입력 허용 ("${messy}")`, added.status === 201 && added.body?.friend?.code === b.code)

  const again = await call('POST', '/v1/friends', { secret: a.secret, body: { code: b.code } })
  check('같은 친구를 두 번 추가해도 안전', again.status === 201)

  // --- 상태 교환 -------------------------------------------------------
  console.log('\nheartbeat')
  await call('POST', '/v1/heartbeat', { secret: a.secret, body: { ...status(20260730, 3, true, 12), name: '경석' } })
  await call('POST', '/v1/heartbeat', { secret: b.secret, body: { ...status(20260730, 1, false, 0, 'focusing'), name: '친구' } })

  const aBeat = await call('POST', '/v1/heartbeat', { secret: a.secret, body: status(20260730, 3, true, 12) })
  const aFriends = aBeat.body?.friends ?? []
  check('A 의 친구 목록에 B 가 있다', aFriends.length === 1 && aFriends[0].code === b.code)
  check('B 의 이름이 보인다', aFriends[0]?.name === '친구')
  check('B 는 아직 못 깨웠다 (activated=false)', aFriends[0]?.activated === false)
  check('B 는 집중 중 (phase=focusing)', aFriends[0]?.phase === 'focusing')
  check('B 의 진행도 1/3', aFriends[0]?.sessions === 1 && aFriends[0]?.goal === 3)

  const bBeat = await call('POST', '/v1/heartbeat', { secret: b.secret, body: status(20260730, 1, false, 0, 'focusing') })
  const bFriends = bBeat.body?.friends ?? []
  check('양방향 — B 의 목록에도 A 가 있다', bFriends.length === 1 && bFriends[0].code === a.code)
  check('A 는 오늘 펫을 깨웠다', bFriends[0]?.activated === true && bFriends[0]?.streak === 12)

  // 서버가 이상한 값을 그대로 믿지 않는지
  const junk = await call('POST', '/v1/heartbeat', {
    secret: b.secret,
    body: { dayKey: 20260730, sessions: 99999, minutes: -50, goal: 999, streak: 5, activated: true, phase: '해킹' },
  })
  const bAfterJunk = (await call('POST', '/v1/heartbeat', { secret: a.secret, body: status(20260730, 3, true, 12) })).body.friends[0]
  check('말도 안 되는 세션 수는 잘린다', bAfterJunk.sessions === 200, String(bAfterJunk.sessions))
  check('음수 시간은 0으로', bAfterJunk.minutes === 0, String(bAfterJunk.minutes))
  check('목표는 20 이하로', bAfterJunk.goal === 20, String(bAfterJunk.goal))
  check('모르는 phase 는 idle 로', bAfterJunk.phase === 'idle', bAfterJunk.phase)

  // --- 펫 그림 ---------------------------------------------------------
  console.log('\npet')
  // 실제 앱은 26x26 PNG 를 보냅니다. 여기서는 형식만 같은 더미로 확인.
  const petData = Buffer.from('가짜-펫-이미지-데이터').toString('base64')
  const petHash = 'abc123def456'

  const noPet = await call('GET', `/v1/pet/${a.code}`, { secret: b.secret })
  check('아직 안 올렸으면 404', noPet.status === 404)

  const upload = await call('PUT', '/v1/pet', { secret: a.secret, body: { pet: petData, petHash } })
  check('내 펫 올리기', upload.status === 200 && upload.body?.petHash === petHash)

  const tooBig = await call('PUT', '/v1/pet', { secret: a.secret, body: { pet: 'A'.repeat(30000), petHash } })
  check('너무 큰 그림은 거절 (413)', tooBig.status === 413)

  const fetched = await call('GET', `/v1/pet/${a.code}`, { secret: b.secret })
  check('친구가 내 펫을 받아간다', fetched.status === 200 && fetched.body?.pet === petData)

  const beatWithPet = await call('POST', '/v1/heartbeat', { secret: b.secret, body: status(20260730, 1, false, 0) })
  const aSeen = beatWithPet.body.friends[0]
  check('평소엔 해시만 오간다 (그림 본문 없음)', aSeen.petHash === petHash && aSeen.pet === undefined)

  // 남의 펫은 못 봐야 합니다.
  const stranger = (await call('POST', '/v1/register', { body: { name: '모르는사람' } })).body
  const peek = await call('GET', `/v1/pet/${a.code}`, { secret: stranger.secret })
  check('친구가 아니면 펫을 볼 수 없다', peek.status === 404)

  // --- 친구 코드 무작위 대입 차단 ---------------------------------------
  console.log('\ncode guessing')
  const guesser = (await call('POST', '/v1/register', { body: { name: '찍는사람' } })).body
  let guessBlocked = null
  // 코드 알파벳에는 0·1·I·L·O 가 없습니다. 형식이 맞아야 실패 카운터까지 도달합니다.
  const ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ'
  for (let i = 0; i < 14; i++) {
    // 실제로 없는 코드들 (형식은 맞음)
    const fake = 'ZZZZZ' + ALPHABET[i]
    const r = await call('POST', '/v1/friends', { secret: guesser.secret, body: { code: fake } })
    if (r.status === 429) { guessBlocked = i; break }
  }
  check('코드를 계속 찍으면 막힌다 (429)', guessBlocked !== null, `${guessBlocked}번째`)
  check('정상 사용 범위(오타 몇 번)에서는 안 막힌다', (guessBlocked ?? 0) >= 10, `${guessBlocked}번째에 차단`)

  const stillOK = await call('POST', '/v1/friends', { secret: a.secret, body: { code: 'ZZZZZZ' } })
  check('차단은 그 사람에게만 적용된다', stillOK.status === 404)

  // --- 쿡 찌르기 -------------------------------------------------------
  console.log('\nnudge')
  const nudgeSelf = await call('POST', '/v1/nudge', { secret: a.secret, body: { code: a.code } })
  check('나를 찌를 수는 없다', nudgeSelf.status === 400)

  const nudgeStranger = await call('POST', '/v1/nudge', { secret: stranger.secret, body: { code: a.code } })
  check('친구가 아니면 못 찌른다 (403)', nudgeStranger.status === 403)

  const poke = await call('POST', '/v1/nudge', { secret: a.secret, body: { code: b.code } })
  check('친구 쿡 찌르기', poke.status === 201 && poke.body?.to === b.code)

  const bInbox = await call('POST', '/v1/heartbeat', { secret: b.secret, body: status(20260730, 1, false, 0) })
  check('찔린 사람이 받아본다', (bInbox.body?.nudges ?? []).length === 1)
  check('누가 찔렀는지 보인다', bInbox.body?.nudges?.[0]?.from === a.code && bInbox.body?.nudges?.[0]?.name === '경석')

  const bAgain = await call('POST', '/v1/heartbeat', { secret: b.secret, body: status(20260730, 1, false, 0) })
  check('같은 찌르기가 두 번 오지 않는다', (bAgain.body?.nudges ?? []).length === 0)

  const spam = await call('POST', '/v1/nudge', { secret: a.secret, body: { code: b.code } })
  check('연달아 찌르면 막힌다 (429)', spam.status === 429 && spam.body?.error === 'nudge_too_soon')
  check('언제 다시 찌를 수 있는지 알려준다', typeof spam.body?.retryAfterMs === 'number' && spam.body.retryAfterMs > 0)

  const aInbox = await call('POST', '/v1/heartbeat', { secret: a.secret, body: status(20260730, 3, true, 12) })
  check('찌른 사람 쪽엔 아무것도 안 온다', (aInbox.body?.nudges ?? []).length === 0)

  // --- 코드 재발급 -----------------------------------------------------
  console.log('\nrotate code')
  const oldCode = a.code
  const rotated = await call('POST', '/v1/code/rotate', { secret: a.secret })
  check('새 코드 발급', rotated.status === 200 && /^[2-9A-HJ-NP-Z]{6}$/.test(rotated.body?.code ?? ''))
  check('예전 코드와 다르다', rotated.body?.code !== oldCode)
  a.code = rotated.body.code

  const oldGone = await call('POST', '/v1/friends', { secret: stranger.secret, body: { code: oldCode } })
  check('예전 코드로는 더 이상 연결 안 된다', oldGone.status === 404)

  const stillFriends = await call('POST', '/v1/heartbeat', { secret: b.secret, body: status(20260730, 1, false, 0) })
  check('기존 친구 관계는 그대로', (stillFriends.body?.friends ?? []).length === 1)
  check('친구 목록에 새 코드가 반영된다', stillFriends.body?.friends?.[0]?.code === a.code)

  // --- 친구 끊기 -------------------------------------------------------
  console.log('\nunfriend')
  const removed = await call('DELETE', `/v1/friends/${b.code}`, { secret: a.secret })
  check('친구 끊기', removed.status === 200)

  const afterA = await call('POST', '/v1/heartbeat', { secret: a.secret, body: status(20260730, 3, true, 12) })
  const afterB = await call('POST', '/v1/heartbeat', { secret: b.secret, body: status(20260730, 1, false, 0) })
  check('A 목록에서 사라짐', (afterA.body?.friends ?? []).length === 0)
  check('양방향 — B 목록에서도 사라짐', (afterB.body?.friends ?? []).length === 0)

  const petAfter = await call('GET', `/v1/pet/${a.code}`, { secret: b.secret })
  check('끊긴 뒤엔 펫도 못 본다', petAfter.status === 404)

  const nudgeAfter = await call('POST', '/v1/nudge', { secret: b.secret, body: { code: a.code } })
  check('끊긴 뒤엔 찌를 수도 없다', nudgeAfter.status === 403)

  // --- 탈퇴 ------------------------------------------------------------
  console.log('\ndelete account')
  const leaver = (await call('POST', '/v1/register', { body: { name: '떠날사람' } })).body
  await call('POST', '/v1/friends', { secret: a.secret, body: { code: leaver.code } })
  const withLeaver = await call('POST', '/v1/heartbeat', { secret: a.secret, body: status(20260730, 3, true, 12) })
  check('탈퇴 전 — 친구 목록에 있다', (withLeaver.body?.friends ?? []).length === 1)

  const left = await call('DELETE', '/v1/me', { secret: leaver.secret })
  check('탈퇴', left.status === 200)

  const ghostToken = await call('GET', '/v1/me', { secret: leaver.secret })
  check('탈퇴 후 토큰이 무효가 된다', ghostToken.status === 401)

  const afterLeave = await call('POST', '/v1/heartbeat', { secret: a.secret, body: status(20260730, 3, true, 12) })
  check('친구 목록에서도 사라진다', (afterLeave.body?.friends ?? []).length === 0)

  const reuse = await call('POST', '/v1/friends', { secret: a.secret, body: { code: leaver.code } })
  check('탈퇴한 사람 코드는 못 찾는다', reuse.status === 404)

  // --- 휴면 계정 정리 ---------------------------------------------------
  if (isLocal) {
    console.log('\ncleanup (휴면 계정 정리)')
    await testCleanup()
  } else {
    console.log('\ncleanup — 로컬에서만 확인 가능하므로 건너뜀')
  }

  // --- 가입 도배 방지 ---------------------------------------------------
  // 일부러 한도까지 채우는 테스트라 운영 서버에서는 돌리지 않습니다.
  // (실제로 걸어버리면 같은 IP 에서 한 시간 동안 진짜 가입이 막힙니다.)
  // 뒤에 오는 테스트가 없도록 맨 마지막에 둡니다.
  if (isLocal) {
    console.log('\nsignup flood')
    let blocked = false
    for (let i = 0; i < 12; i++) {
      const r = await call('POST', '/v1/register', { body: { name: `봇${i}` } })
      if (r.status === 429) {
        blocked = true
        check('가입을 쏟아부으면 막힌다 (429)', r.body?.error === 'register_rate_limited')
        break
      }
    }
    check('한도가 실제로 작동한다', blocked)
  } else {
    console.log('\nsignup flood — 운영 서버의 가입을 실제로 막게 되므로 건너뜀')
  }

  console.log(`\n${passed} 통과, ${failed} 실패\n`)
  process.exit(failed === 0 ? 0 : 1)
}

/**
 * 휴면 계정 정리는 "며칠 지났는가"가 조건이라, 로컬 DB 의 시각을 과거로 돌려놓고 확인합니다.
 * wrangler 로 직접 UPDATE 하므로 로컬에서만 돕니다.
 */
async function testCleanup() {
  const day = 24 * 60 * 60 * 1000
  const now = Date.now()

  const make = async (label) => (await call('POST', '/v1/register', { body: { name: label } })).body

  const neverUsedOld = await make('가입만하고8일') // 지워져야 함
  const neverUsedNew = await make('가입만하고어제') // 남아야 함
  const idleSolo = await make('친구없이100일') // 지워져야 함
  const idleWithFriend1 = await make('친구있고100일A') // 남아야 함
  const idleWithFriend2 = await make('친구있고100일B')

  await call('POST', '/v1/friends', { secret: idleWithFriend1.secret, body: { code: idleWithFriend2.code } })

  const sql = [
    `UPDATE users SET created_at=${now - 8 * day}, updated_at=${now - 8 * day} WHERE id='${neverUsedOld.userId}'`,
    `UPDATE users SET created_at=${now - 1 * day}, updated_at=${now - 1 * day} WHERE id='${neverUsedNew.userId}'`,
    `UPDATE users SET created_at=${now - 200 * day}, updated_at=${now - 100 * day} WHERE id='${idleSolo.userId}'`,
    `UPDATE users SET created_at=${now - 200 * day}, updated_at=${now - 100 * day} WHERE id='${idleWithFriend1.userId}'`,
    `UPDATE users SET created_at=${now - 200 * day}, updated_at=${now - 100 * day} WHERE id='${idleWithFriend2.userId}'`,
  ].join('; ')

  const { execSync } = await import('node:child_process')
  execSync(`npx wrangler d1 execute pomopet-sync --local --command ${JSON.stringify(sql)}`, {
    stdio: 'ignore',
  })

  const ran = await fetch(`${BASE}/__scheduled?cron=0+4+*+*+*`)
  check('정리 작업이 돈다', ran.ok)
  await new Promise((r) => setTimeout(r, 500))

  const alive = async (user) => (await call('GET', '/v1/me', { secret: user.secret })).status === 200

  check('가입만 하고 8일 지난 계정 — 삭제', !(await alive(neverUsedOld)))
  check('가입만 하고 어제 만든 계정 — 유지', await alive(neverUsedNew))
  check('친구 없이 100일 방치 — 삭제', !(await alive(idleSolo)))
  check('친구 있으면 100일 방치해도 유지', await alive(idleWithFriend1))
  check('친구 쪽 계정도 유지', await alive(idleWithFriend2))
}

main().catch((err) => {
  console.error('\n테스트 실행 실패:', err.message)
  console.error('서버가 떠 있는지 확인하세요 (npm run dev)\n')
  process.exit(1)
})
