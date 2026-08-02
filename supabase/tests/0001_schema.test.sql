-- T4 — 0001_schema.sql 이 만든 그릇을 검사한다.
--
-- 실행: supabase db reset && supabase test db --local
-- pgTAP 자체는 로컬 전용이라 `supabase/seed.sql` 에서 설치한다(원격 마이그레이션 오염 방지).

begin;
select plan(25);

-- 확장 --------------------------------------------------------------------
-- postgis/btree_gist 는 `extensions` 스키마에 둔다. pg_cron 은 컨트롤 파일이
-- 스키마를 pg_catalog 로 고정하므로 위치를 검사하지 않는다.
select has_extension('extensions', 'postgis', 'postgis 는 extensions 스키마에 있다');
select has_extension('extensions', 'btree_gist', 'btree_gist 는 extensions 스키마에 있다');
select has_extension('pg_cron', 'pg_cron 이 설치돼 있다');

-- 타입 --------------------------------------------------------------------
select has_enum('public', 'weather_state', 'weather_state enum 이 있다');
select enum_has_labels(
  'public', 'weather_state',
  array['clear', 'partly_cloudy', 'cloudy', 'rain', 'snow', 'hail', 'wind', 'fog', 'dust'],
  'weather_state 는 문서 순서대로 9개 값을 가진다'
);
select has_enum('public', 'vote_kind', 'vote_kind enum 이 있다');
select enum_has_labels(
  'public', 'vote_kind', array['confirm', 'dispute'],
  'vote_kind 는 confirm/dispute 두 값'
);
select has_enum('public', 'flag_reason', 'flag_reason enum 이 있다');
select enum_has_labels(
  'public', 'flag_reason', array['wrong', 'spam', 'other'],
  'flag_reason 은 wrong/spam/other 세 값'
);

-- 테이블 ------------------------------------------------------------------
select tables_are(
  'public',
  array[
    'profiles', 'weather_state_lifespans', 'reports', 'report_votes',
    'report_flags', 'watched_areas', 'alert_sends', 'kma_observations'
  ],
  'public 스키마에는 문서에 적힌 8개 테이블만 있다'
);

select columns_are(
  'public', 'reports',
  array[
    'id', 'user_id', 'state', 'cell_point', 'cell_id', 'kma_nx', 'kma_ny',
    'raw_point', 'raw_accuracy_m', 'observed_at', 'expires_at', 'created_at'
  ],
  'reports 는 공개 격자 컬럼과 서버 전용 원좌표 컬럼을 함께 가진다'
);

-- 원좌표는 24시간 뒤 NULL 로 지워진다(ADR-0002). NOT NULL 이면 폐기가 불가능하다.
select col_is_null('public', 'reports', 'raw_point', 'reports.raw_point 는 NULL 이 될 수 있다');
select col_is_null(
  'public', 'report_votes', 'raw_point', 'report_votes.raw_point 는 NULL 이 될 수 있다'
);

-- 한 유저는 한 제보에 한 번만 투표한다 — 애플리케이션이 아니라 키가 보장한다.
select col_is_pk(
  'public', 'report_votes', array['report_id', 'user_id'],
  'report_votes 의 기본키는 (report_id, user_id)'
);
select col_is_pk(
  'public', 'kma_observations', array['nx', 'ny', 'base_at'],
  'kma_observations 의 기본키는 (nx, ny, base_at)'
);

-- 수명표 ------------------------------------------------------------------
select is(
  (select count(*)::int from weather_state_lifespans), 9,
  'weather_state_lifespans 는 정확히 9행 (상태 하나도 빠지지 않는다)'
);
select results_eq(
  $$ select state::text, lifespan from weather_state_lifespans order by state::text $$,
  $$ values ('clear', '1 hour'::interval),
            ('cloudy', '1 hour'::interval),
            ('dust', '2 hours'::interval),
            ('fog', '2 hours'::interval),
            ('hail', '30 minutes'::interval),
            ('partly_cloudy', '1 hour'::interval),
            ('rain', '30 minutes'::interval),
            ('snow', '2 hours'::interval),
            ('wind', '30 minutes'::interval) $$,
  '수명은 문서에 적힌 값과 같다'
);

-- 인덱스 ------------------------------------------------------------------
select has_index(
  'public', 'reports', 'reports_live_idx',
  '반경 조회용 gist(cell_point, expires_at) — 만료분을 인덱스 단계에서 잘라낸다'
);
select has_index('public', 'reports', 'reports_user_recent', 'reports_user_recent 인덱스가 있다');
select has_index('public', 'reports', 'reports_cell_live', 'reports_cell_live 인덱스가 있다');
select has_index(
  'public', 'reports', 'reports_purge_idx',
  'reports_purge_idx 는 원좌표가 남은 행만 훑는 부분 인덱스'
);
select has_index(
  'public', 'reports', 'reports_user_cell_state', 'reports_user_cell_state 인덱스가 있다'
);
select has_index(
  'public', 'watched_areas', 'watched_areas_user_label',
  '같은 label 을 두 번 등록할 수 없다'
);

-- auth.users -> profiles 트리거 --------------------------------------------
select has_trigger(
  'auth', 'users', 'on_auth_user_created', 'auth.users 에 프로필 생성 트리거가 걸려 있다'
);

insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000a1');
select is(
  (select count(*)::int from profiles where id = '00000000-0000-0000-0000-0000000000a1'),
  1,
  '익명 유저가 생기면 profiles 행이 자동으로 따라 만들어진다'
);

select * from finish();
rollback;
