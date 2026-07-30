-- 이미 운영 중인 DB 를 새 스키마로 맞춥니다.
--   * 원본 IP 를 버리고 해시 컬럼으로 교체 (개인정보 최소화)
--   * 친구 코드 무작위 대입을 막을 실패 횟수 컬럼 추가
--   * IP 해시용 소금을 담을 meta 테이블 추가
--
-- 순서 주의: 인덱스가 컬럼을 참조하고 있으면 그 컬럼을 지울 수 없습니다.
-- 인덱스를 먼저 없애고, 컬럼을 지우고, 새 컬럼으로 다시 만듭니다.

DROP INDEX IF EXISTS idx_users_signup_ip;

ALTER TABLE users ADD COLUMN signup_ip TEXT;
ALTER TABLE users ADD COLUMN friend_fails INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN friend_fail_at INTEGER NOT NULL DEFAULT 0;

-- 지금까지 쌓인 원본 IP 는 통째로 버립니다.
ALTER TABLE users DROP COLUMN created_ip;

CREATE INDEX IF NOT EXISTS idx_users_signup_ip ON users(signup_ip, created_at);

CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
