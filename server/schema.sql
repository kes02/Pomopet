-- Pomopet 친구 연동 서버 스키마 (Cloudflare D1 / SQLite)
--
-- 설계 원칙
--  * 계정 없음: 앱이 최초 실행 때 익명 사용자를 만들고 secret 을 Keychain 에 보관합니다.
--  * 집계값만: 하루 세션 수·집중 시간·활성 여부·스트릭만 저장합니다. 시각별 로그는 받지 않습니다.
--  * 펫 그림은 별도 컬럼: 바뀔 때만 올리고, 평소엔 해시만 주고받습니다.

CREATE TABLE IF NOT EXISTS users (
  id          TEXT    PRIMARY KEY,              -- uuid
  code        TEXT    NOT NULL UNIQUE,          -- 친구에게 알려주는 6자리 코드
  secret_hash TEXT    NOT NULL UNIQUE,          -- sha256(secret). 원본은 서버에 남기지 않음
  name        TEXT    NOT NULL DEFAULT '',      -- 친구 목록에 보이는 이름
  day_key     INTEGER NOT NULL DEFAULT 0,       -- yyyyMMdd
  sessions    INTEGER NOT NULL DEFAULT 0,       -- 그날 완료한 집중 세션 수
  minutes     INTEGER NOT NULL DEFAULT 0,       -- 그날 누적 집중 시간(분)
  goal        INTEGER NOT NULL DEFAULT 1,       -- 그 사람의 하루 목표 세션 수
  activated   INTEGER NOT NULL DEFAULT 0,       -- 오늘 펫이 깨어났는지 (0/1)
  streak      INTEGER NOT NULL DEFAULT 0,       -- 현재 연속일
  phase       TEXT    NOT NULL DEFAULT 'idle',  -- idle | focusing | breakReady | resting
  pet_hash    TEXT,                             -- 펫 그림 해시 (변경 감지용)
  pet         TEXT,                             -- 26x26 PNG base64
  signup_ip   TEXT,                             -- 가입 도배 차단용 IP 해시(원본 아님). 하루 뒤 지워짐
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,                 -- 마지막 heartbeat. 휴면 계정 판단 기준

  -- 친구 코드 무작위 대입 차단용. 실패한 시도만 셉니다.
  friend_fails   INTEGER NOT NULL DEFAULT 0,
  friend_fail_at INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_users_idle ON users(updated_at);
CREATE INDEX IF NOT EXISTS idx_users_signup_ip ON users(signup_ip, created_at);

-- 친구 관계는 항상 양방향으로 두 줄 넣습니다 (조회를 단순하게 유지).
CREATE TABLE IF NOT EXISTS friendships (
  user_id    TEXT    NOT NULL,
  friend_id  TEXT    NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, friend_id)
);

CREATE INDEX IF NOT EXISTS idx_friendships_user ON friendships(user_id);

-- 쿡 찌르기.
-- 애플 푸시(APNs)는 유료 계정이 있어야 쓸 수 있어서, 찌른 기록을 여기 쌓아두고
-- 상대 앱이 heartbeat 할 때 받아갑니다. 메뉴바 앱이라 늘 떠 있어서 보통 1분 안에 전달됩니다.
-- 받아간 뒤에도 지우지 않고 delivered_at 만 채웁니다 — 도배 방지 횟수를 세야 하기 때문입니다.
CREATE TABLE IF NOT EXISTS nudges (
  id           TEXT    PRIMARY KEY,
  to_id        TEXT    NOT NULL,
  from_id      TEXT    NOT NULL,
  created_at   INTEGER NOT NULL,
  delivered_at INTEGER              -- NULL 이면 상대가 아직 못 받아간 상태
);

CREATE INDEX IF NOT EXISTS idx_nudges_inbox ON nudges(to_id, delivered_at, created_at);
CREATE INDEX IF NOT EXISTS idx_nudges_sent ON nudges(from_id, to_id, created_at);

-- 서버 자체 설정값. 지금은 IP 해시용 소금 하나만 들어갑니다.
-- 소금은 첫 가입 때 무작위로 만들어져 이 DB 안에만 존재합니다 — 직접 띄운 서버마다 값이 다릅니다.
CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
