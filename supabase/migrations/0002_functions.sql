-- 0002_functions.sql — 좌표를 격자로 바꾸고, 제보의 수명을 정한다.
--
-- 원문은 docs/data-model.md 의 "함수" 절이다. 여기까지는 아직 클라이언트 진입점이
-- 아니다(RPC 는 0003). 이 파일의 snap_to_cell 이 원좌표를 격자 중심으로 바꾸는
-- 유일한 지점이며, ADR-0002 의 개인정보 약속은 여기서 시작된다.

-- snap_to_cell — 100m 격자 스냅 --------------------------------------------
-- EPSG:5179(Korea 2000 / Unified CS)로 투영해 미터 단위로 자른다. 위경도를 그냥
-- 반올림하면 경도 1도의 실제 거리가 위도마다 달라 격자가 찌그러진다.
-- 셀 모서리가 아니라 중심(+50)을 돌려주는 이유는 지도에서 핀이 한쪽으로 쏠려
-- 보이지 않게 하기 위해서다.
create or replace function snap_to_cell(p geography)
returns table (cell geography, cell_id text)
language sql immutable parallel safe as $$
  with m as (select st_transform(p::geometry, 5179) as g),
       s as (select floor(st_x(g) / 100)::int as gx,
                    floor(st_y(g) / 100)::int as gy from m)
  select st_transform(st_setsrid(st_makepoint(gx * 100 + 50, gy * 100 + 50), 5179), 4326)::geography,
         gx || ':' || gy
  from s;
$$;

-- kma_grid — 기상청 격자 변환 ----------------------------------------------
-- 기상청 단기예보 API 가 쓰는 Lambert Conformal Conic 변환. 상수는 기상청 배포
-- 문서의 값이며 임의로 바꾸면 실황이 엉뚱한 동네 것이 된다.
create or replace function kma_grid(lat double precision, lng double precision)
returns table (nx smallint, ny smallint)
language plpgsql immutable parallel safe as $$
declare
  re    constant double precision := 6371.00877 / 5.0;   -- 지구반경 / 격자간격(km)
  slat1 constant double precision := radians(30.0);
  slat2 constant double precision := radians(60.0);
  olon  constant double precision := radians(126.0);
  olat  constant double precision := radians(38.0);
  sn double precision; sf double precision; ro double precision;
  ra double precision; theta double precision;
begin
  sn := ln(cos(slat1) / cos(slat2))
        / ln(tan(pi() * 0.25 + slat2 * 0.5) / tan(pi() * 0.25 + slat1 * 0.5));
  sf := power(tan(pi() * 0.25 + slat1 * 0.5), sn) * cos(slat1) / sn;
  ro := re * sf / power(tan(pi() * 0.25 + olat * 0.5), sn);
  ra := re * sf / power(tan(pi() * 0.25 + radians(lat) * 0.5), sn);

  theta := radians(lng) - olon;
  if theta >  pi() then theta := theta - 2 * pi(); end if;
  if theta < -pi() then theta := theta + 2 * pi(); end if;
  theta := theta * sn;

  nx := floor(ra * sin(theta) + 43  + 0.5)::smallint;
  ny := floor(ro - ra * cos(theta) + 136 + 0.5)::smallint;
  return next;
end $$;

-- report_lifespan -----------------------------------------------------------
-- 수명은 코드가 아니라 weather_state_lifespans 표에 있다. 운영 중에 "비는 30분이
-- 너무 짧다"가 나오면 배포 없이 한 행만 고친다.
create or replace function report_lifespan(s weather_state)
returns interval language sql stable as $$
  select lifespan from weather_state_lifespans where state = s;
$$;
