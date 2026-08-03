-- T5 — 0002_functions.sql 의 좌표 변환·수명 함수를 검사한다.
--
-- 실행: supabase db reset && supabase test db
--
-- 여기서 검사하는 것은 "개인정보 보호의 핵심 부품"이다(ADR-0002). snap_to_cell 이
-- 원좌표를 격자 중심으로 바꾸지 못하면 그 뒤의 모든 잠금장치(T7 RLS)가 무의미해진다.

begin;
select plan(5);

-- 기상청 격자 변환 ---------------------------------------------------------
-- 서울시청 좌표는 기상청 배포 문서의 검증값이다. LCC 상수를 하나라도 잘못 옮기면
-- 여기서 어긋난다.
select results_eq(
  $$ select nx::int, ny::int from kma_grid(37.5665, 126.9780) $$,
  $$ values (60, 127) $$,
  '서울시청(37.5665, 126.9780) 은 기상청 격자 nx=60, ny=127 이다'
);

-- 100m 격자 스냅 -----------------------------------------------------------
-- 100m 정사각형 격자의 중심과 격자 내 임의 점의 최대 거리는 대각선 절반,
-- 즉 sqrt(2) * 50 ~= 70.7m 다. 71m 를 넘으면 격자 크기나 투영이 잘못된 것이다.
select ok(
  (select st_distance(cell, st_setsrid(st_makepoint(126.9780, 37.5665), 4326)::geography)
     from snap_to_cell(st_setsrid(st_makepoint(126.9780, 37.5665), 4326)::geography)) <= 71.0,
  '스냅된 격자 중심은 원좌표에서 71m 이내다 (100m 격자의 대각선 절반)'
);

-- 셀 중심을 다시 스냅해도 같은 셀이어야 한다. 중심이 격자 안에 있다는 뜻이고,
-- 격자 모서리를 반환하고 있었다면 여기서 이웃 셀로 새어나간다.
select is(
  (select cell_id from snap_to_cell(
     (select cell from snap_to_cell(st_setsrid(st_makepoint(126.9780, 37.5665), 4326)::geography)))),
  (select cell_id from snap_to_cell(st_setsrid(st_makepoint(126.9780, 37.5665), 4326)::geography)),
  '격자 중심을 다시 스냅하면 같은 cell_id 다 (중심은 자기 격자 안에 있다)'
);

-- 100m 보다 훨씬 멀리 떨어진 두 점은 반드시 다른 격자에 속한다. 이 검사가 깨지면
-- 스냅 단위가 100m 가 아니라는 뜻이다.
select isnt(
  (select cell_id from snap_to_cell(st_setsrid(st_makepoint(126.9780, 37.5665), 4326)::geography)),
  (select cell_id from snap_to_cell(st_setsrid(st_makepoint(126.9830, 37.5665), 4326)::geography)),
  '약 440m 떨어진 두 점은 다른 격자에 들어간다'
);

-- 수명 ---------------------------------------------------------------------
-- report_lifespan 은 수명표를 읽는 얇은 함수다. 9개 상태 중 하나라도 NULL 이
-- 나오면 제보의 expires_at 이 NULL 이 되어 영원히 만료되지 않는다.
select results_eq(
  $$ select s::text, report_lifespan(s)
       from unnest(enum_range(null::weather_state)) as s
      order by s::text $$,
  $$ select state::text, lifespan from weather_state_lifespans order by state::text $$,
  'report_lifespan 은 9개 상태 전부에 대해 수명표와 같은 값을 준다'
);

select * from finish();
rollback;
