-- 로컬 개발용 초기화. `npm run db:reset` 이 이걸 먼저 돌리고 schema.sql 을 다시 적용합니다.
-- 운영 DB 에는 절대 쓰지 마세요.
DROP TABLE IF EXISTS nudges;
DROP TABLE IF EXISTS friendships;
DROP TABLE IF EXISTS users;
