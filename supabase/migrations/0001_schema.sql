-- 0001_schema.sql — 제보를 담을 그릇.
--
-- 원문은 docs/data-model.md 다. 이 파일은 그 계약을 실행 가능한 형태로 옮긴 것이며,
-- 함수/RPC(0002, 0003)와 권한/RLS(0004)는 여기 없다. 이 시점의 DB 는 아직 잠겨 있지 않다.

-- 확장 --------------------------------------------------------------------
-- 로컬 스택에는 postgis/btree_gist 가 이미 extensions 스키마에 깔려 있어 no-op 이지만,
-- 원격 프로젝트(T24)에는 없으므로 마이그레이션이 직접 책임진다.
create extension if not exists postgis with schema extensions;
create extension if not exists btree_gist with schema extensions;

-- pg_cron 은 컨트롤 파일이 스키마를 pg_catalog 로 고정한다. `with schema extensions` 를
-- 붙여도 무시되므로 붙이지 않는다. 실제 cron 등록은 T22/T23 에서 한다.
create extension if not exists pg_cron;

-- 타입 --------------------------------------------------------------------
-- UI 의 "기타"는 도메인 값이 아니다. 6버튼 중 마지막 버튼이 뒤의 4개를 접어둔
-- 화면상의 묶음일 뿐이고, 저장되는 값은 항상 구체적인 상태다.
create type weather_state as enum (
  'clear',          -- 맑음
  'partly_cloudy',  -- 구름많음
  'cloudy',         -- 흐림
  'rain',           -- 비
  'snow',           -- 눈
  'hail',           -- 우박
  'wind',           -- 강풍
  'fog',            -- 안개
  'dust'            -- 황사
);

create type vote_kind   as enum ('confirm', 'dispute');
create type flag_reason as enum ('wrong', 'spam', 'other');

-- 테이블 ------------------------------------------------------------------

-- 익명 인증 유저도 auth.users 에 행이 생기므로 그대로 쓴다.
-- banned_at 은 신고 누적 시 운영자가 채우는 칼럼이며, 앱스토어가 요구하는
-- "악성 유저 차단 수단"에 해당한다.
create table profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  push_token text,
  banned_at  timestamptz,
  created_at timestamptz not null default now()
);

-- 코드에 CASE 로 박지 않고 테이블로 둔 이유는 배포 없이 조정하기 위해서다.
-- 이 숫자들은 실제 데이터를 보기 전까지 추측이고, 출시 후 몇 번 고칠 것이 확실하다.
create table weather_state_lifespans (
  state    weather_state primary key,
  lifespan interval not null
);

insert into weather_state_lifespans (state, lifespan) values
  ('rain', '30 minutes'), ('hail', '30 minutes'), ('wind', '30 minutes'),
  ('snow', '2 hours'),    ('fog',  '2 hours'),    ('dust', '2 hours'),
  ('clear', '1 hour'),    ('partly_cloudy', '1 hour'), ('cloudy', '1 hour');

create table reports (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  state          weather_state not null,

  -- 공개: 100m 격자로 스냅된 위치
  cell_point     geography(Point, 4326) not null,
  cell_id        text not null,
  kma_nx         smallint not null,
  kma_ny         smallint not null,

  -- 서버 전용: 24시간 후 NULL (ADR-0002)
  raw_point      geography(Point, 4326),
  raw_accuracy_m real,

  observed_at    timestamptz not null default now(),
  -- 제보 시점에 report_lifespan(state) 으로 계산해 고정한다. 조회할 때마다
  -- 상태별 수명을 조인해서 계산하면 인덱스를 못 탄다.
  expires_at     timestamptz not null,
  created_at     timestamptz not null default now()
);

-- 반경 조회는 항상 "공간 조건 AND 아직 안 만료됨"을 동시에 건다. 공간 인덱스만 있으면
-- 만료된 제보까지 전부 긁고 나서 걸러낸다. btree_gist 로 두 조건을 한 인덱스에 넣으면
-- 만료분을 인덱스 단계에서 잘라낸다.
create index reports_live_idx    on reports using gist (cell_point, expires_at);
create index reports_user_recent on reports (user_id, created_at desc);
create index reports_cell_live   on reports (cell_id, expires_at desc);

-- 부분 인덱스. 원좌표가 남아 있는 행은 최근 24시간치뿐이므로 테이블이 아무리 커져도
-- purge 작업이 훑는 범위는 일정하게 유지된다.
create index reports_purge_idx   on reports (created_at) where raw_point is not null;
create index reports_user_cell_state on reports (user_id, cell_id, state, expires_at desc);

-- 복합 기본키가 "한 유저는 한 제보에 한 번만 투표"를 DB 차원에서 보장한다.
-- 투표자의 원좌표를 저장하는 이유는 검증 때문이다 — 투표가 유효하려면 투표자가 제보
-- 위치 근처에 있어야 하고, 그 판정은 서버가 해야 한다. 이것도 24시간 후 지운다.
create table report_votes (
  report_id  uuid not null references reports (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  vote       vote_kind not null,
  raw_point  geography(Point, 4326),   -- 24시간 후 NULL
  created_at timestamptz not null default now(),
  primary key (report_id, user_id)
);

create index report_votes_purge_idx on report_votes (created_at) where raw_point is not null;

create table report_flags (
  report_id  uuid not null references reports (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  reason     flag_reason not null,
  created_at timestamptz not null default now(),
  primary key (report_id, user_id)
);

-- 관심 지역도 격자로만 저장한다. 유저가 등록하는 곳은 대개 집이므로 제보보다 민감하다.
create table watched_areas (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  label      text not null,
  cell_point geography(Point, 4326) not null,
  cell_id    text not null,
  kma_nx     smallint not null,
  kma_ny     smallint not null,
  created_at timestamptz not null default now()
);

create unique index watched_areas_user_label on watched_areas (user_id, label);
create index        watched_areas_cell_idx   on watched_areas (cell_id);

-- 3시간 쿨다운(ADR-0005) 판정 전용 테이블.
create table alert_sends (
  id              bigserial primary key,
  watched_area_id uuid not null references watched_areas (id) on delete cascade,
  state           weather_state not null,
  sent_at         timestamptz not null default now()
);

create index alert_sends_cooldown on alert_sends (watched_area_id, sent_at desc);

-- 기상청 실황 캐시. 같은 격자의 유저가 100명이어도 API 호출은 1회다.
create table kma_observations (
  nx         smallint not null,
  ny         smallint not null,
  base_at    timestamptz not null,
  sky        smallint,        -- 1 맑음 / 3 구름많음 / 4 흐림
  pty        smallint,        -- 0 없음 / 1 비 / 2 비눈 / 3 눈 / 5 빗방울 / 6 빗방울눈날림 / 7 눈날림
  rn1        real,            -- 1시간 강수량
  t1h        real,            -- 기온
  fetched_at timestamptz not null default now(),
  primary key (nx, ny, base_at)
);

-- auth.users -> profiles --------------------------------------------------
-- 로그인 UI 가 없으므로(T8) 프로필 생성도 앱이 시킬 자리가 없다. 익명 가입 시점에
-- 서버가 만든다.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();
