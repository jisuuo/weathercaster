# 데이터 모델

확정 전 초안. 결정 근거는 `docs/adr/`, 용어는 `CONTEXT.md` 참조.

## 접근 원칙

**모든 테이블은 RLS를 켜되 정책을 만들지 않는다 (= 전면 거부).** 클라이언트는 테이블에 직접 접근하지
못하고, 오직 `SECURITY DEFINER` RPC를 통해서만 읽고 쓴다.

읽기까지 RPC로 묶는 이유는 원좌표 때문이다. RLS는 행 단위로만 판단하므로 "이 행은 보여주되 `raw_point`
컬럼만 가린다"를 표현할 수 없다. 컬럼 단위 `REVOKE`로 흉내낼 수는 있지만, `select *` 한 번에 깨지고
새 컬럼을 추가할 때마다 다시 실수할 여지가 남는다. 기본 테이블을 통째로 닫고 RPC가 공개 컬럼만 골라
반환하면 이 실수 자체가 불가능해진다.

모든 `SECURITY DEFINER` 함수는 `SET search_path = public, pg_temp`를 붙인다. 빠뜨리면 권한 상승 경로가
열린다.

```sql
create extension if not exists postgis;
create extension if not exists btree_gist;
create extension if not exists pg_cron;
```

## 타입

```sql
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

create type vote_kind  as enum ('confirm', 'dispute');
create type flag_reason as enum ('wrong', 'spam', 'other');
```

UI의 "기타"는 도메인 값이 아니다. 6버튼 중 마지막 버튼이 뒤의 4개(`hail`/`wind`/`fog`/`dust`)를 접어둔
화면상의 묶음일 뿐이며, 저장되는 값은 항상 구체적인 상태다.

## 테이블

### profiles

```sql
create table profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  push_token text,
  banned_at  timestamptz,
  created_at timestamptz not null default now()
);
```

익명 인증 유저도 `auth.users`에 행이 생기므로 그대로 쓴다. `banned_at`은 신고 누적 시 운영자가 채우는
칼럼이며, 앱스토어가 요구하는 "악성 유저 차단 수단"에 해당한다.

### weather_state_lifespans

```sql
create table weather_state_lifespans (
  state    weather_state primary key,
  lifespan interval not null
);

insert into weather_state_lifespans (state, lifespan) values
  ('rain', '30 minutes'), ('hail', '30 minutes'), ('wind', '30 minutes'),
  ('snow', '2 hours'),    ('fog',  '2 hours'),    ('dust', '2 hours'),
  ('clear', '1 hour'),    ('partly_cloudy', '1 hour'), ('cloudy', '1 hour');
```

코드에 `CASE`로 박지 않고 테이블로 둔 이유는 배포 없이 조정하기 위해서다. 이 숫자들은 실제 데이터를
보기 전까지는 추측이고, 출시 후 몇 번 고칠 것이 확실하다.

### reports

```sql
create table reports (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
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
  expires_at     timestamptz not null,
  created_at     timestamptz not null default now()
);

create index reports_live_idx    on reports using gist (cell_point, expires_at);
create index reports_user_recent on reports (user_id, created_at desc);
create index reports_cell_live   on reports (cell_id, expires_at desc);
create index reports_purge_idx   on reports (created_at) where raw_point is not null;
create index reports_user_cell_state on reports (user_id, cell_id, state, expires_at desc);
```

`reports_live_idx`가 핵심이다. 반경 조회는 항상 "공간 조건 AND 아직 안 만료됨" 두 가지를 동시에 거는데,
공간 인덱스만 있으면 만료된 제보까지 전부 긁고 나서 걸러내게 된다. `btree_gist` 확장을 써서 두 조건을
한 인덱스에 넣으면 만료분을 인덱스 단계에서 잘라낸다. 제보가 쌓일수록 이 차이가 커진다.

`expires_at`은 제보 시점에 `report_lifespan(state)`으로 계산해 고정한다. 조회할 때마다 상태별 수명을
조인해서 계산하면 인덱스를 못 탄다.

`reports_purge_idx`는 부분 인덱스다. 원좌표가 남아 있는 행은 최근 24시간치뿐이므로, 전체 테이블이 아무리
커져도 purge 작업이 훑는 범위는 일정하게 유지된다.

### report_votes

```sql
create table report_votes (
  report_id  uuid not null references reports(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  vote       vote_kind not null,
  raw_point  geography(Point, 4326),   -- 24시간 후 NULL
  created_at timestamptz not null default now(),
  primary key (report_id, user_id)
);

create index report_votes_purge_idx on report_votes (created_at) where raw_point is not null;
```

복합 기본키가 "한 유저는 한 제보에 한 번만 투표"를 DB 차원에서 보장한다. 애플리케이션 로직에 맡기지
않는다.

투표자의 원좌표를 저장하는 이유는 검증 때문이다 — 투표가 유효하려면 투표자가 제보 위치 근처에 있어야
하고, 그 판정은 서버가 해야 한다. 이것도 24시간 후 지운다.

### report_flags

```sql
create table report_flags (
  report_id  uuid not null references reports(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  reason     flag_reason not null,
  created_at timestamptz not null default now(),
  primary key (report_id, user_id)
);
```

### watched_areas

```sql
create table watched_areas (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  label      text not null,
  cell_point geography(Point, 4326) not null,
  cell_id    text not null,
  kma_nx     smallint not null,
  kma_ny     smallint not null,
  created_at timestamptz not null default now()
);

create unique index watched_areas_user_label on watched_areas (user_id, label);
create index        watched_areas_cell_idx   on watched_areas (cell_id);
```

관심 지역도 격자로만 저장한다. 유저가 등록하는 곳은 대개 집이므로, 오히려 제보보다 민감하다.

### alert_sends

```sql
create table alert_sends (
  id              bigserial primary key,
  watched_area_id uuid not null references watched_areas(id) on delete cascade,
  state           weather_state not null,
  sent_at         timestamptz not null default now()
);

create index alert_sends_cooldown on alert_sends (watched_area_id, sent_at desc);
```

3시간 쿨다운(ADR-0005) 판정 전용 테이블이다.

### kma_observations

```sql
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
```

기상청 실황 캐시. 같은 격자의 유저가 100명이어도 API 호출은 1회다. 기상청 API 키는 Edge Function에만
두고 앱 번들에 넣지 않는다.

## 함수

### snap_to_cell — 100m 격자 스냅

```sql
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
```

EPSG:5179(Korea 2000 / Unified CS)로 투영해서 미터 단위로 자른다. 위경도를 그냥 반올림하면 격자가 위도에
따라 찌그러진다 — 경도 1도의 실제 거리가 위도마다 다르기 때문이다. 어차피 한국 전용 앱이므로 한국
좌표계를 쓰는 것이 맞다.

셀 중심(`+50`)을 쓰는 이유는 격자 모서리를 반환하면 지도에서 핀이 한쪽으로 쏠려 보이기 때문이다.

### kma_grid — 기상청 격자 변환

```sql
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
```

기상청 단기예보 API가 쓰는 Lambert Conformal Conic 변환이다. 상수는 기상청 배포 문서의 값이다.

### report_lifespan

```sql
create or replace function report_lifespan(s weather_state)
returns interval language sql stable as $$
  select lifespan from weather_state_lifespans where state = s;
$$;
```

## RPC (클라이언트 진입점)

### submit_report

```sql
create or replace function submit_report(
  p_state      weather_state,
  p_lat        double precision,
  p_lng        double precision,
  p_accuracy_m real    default null,
  p_is_mocked  boolean default false
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_raw  geography := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
  v_cell geography; v_cell_id text;
  v_last reports%rowtype;
  v_kmh  double precision;
  v_nx smallint; v_ny smallint; v_id uuid;
begin
  if v_user is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if exists (select 1 from profiles where id = v_user and banned_at is not null) then
    raise exception 'BANNED';
  end if;

  -- Android가 목 위치를 보고한 경우 (iOS는 이 신호가 없음)
  if p_is_mocked then
    raise exception 'MOCK_LOCATION';
  end if;

  if p_accuracy_m is not null and p_accuracy_m > 200 then
    raise exception 'LOW_ACCURACY';
  end if;

  select * into v_last
  from reports where user_id = v_user
  order by created_at desc limit 1;

  -- 오폭·중복 전송 방지용 최소 간격 (ADR-0006)
  if v_last.id is not null and v_last.created_at > now() - interval '30 seconds' then
    raise exception 'TOO_SOON';
  end if;

  if (select count(*) from reports
       where user_id = v_user and created_at > now() - interval '24 hours') >= 100 then
    raise exception 'DAILY_LIMIT';
  end if;

  -- 이동 속도 검증: 직전 제보에서 여기까지 물리적으로 올 수 있었나
  if v_last.raw_point is not null then
    v_kmh := st_distance(v_last.raw_point, v_raw)
             / greatest(extract(epoch from now() - v_last.created_at), 1) * 3.6;
    if v_kmh > 900 then
      raise exception 'IMPOSSIBLE_SPEED';
    end if;
  end if;

  select cell, cell_id into v_cell, v_cell_id from snap_to_cell(v_raw);
  select nx, ny         into v_nx,  v_ny      from kma_grid(p_lat, p_lng);

  -- 같은 격자·같은 상태를 다시 제보하면 새 행이 아니라 수명 연장 (ADR-0006)
  update reports
     set observed_at    = now(),
         expires_at     = now() + report_lifespan(p_state),
         raw_point      = v_raw,
         raw_accuracy_m = p_accuracy_m
   where user_id = v_user
     and cell_id = v_cell_id
     and state   = p_state
     and expires_at > now()
  returning id into v_id;

  if v_id is not null then
    return v_id;
  end if;

  insert into reports (user_id, state, cell_point, cell_id, kma_nx, kma_ny,
                       raw_point, raw_accuracy_m, expires_at)
  values (v_user, p_state, v_cell, v_cell_id, v_nx, v_ny,
          v_raw, p_accuracy_m, now() + report_lifespan(p_state))
  returning id into v_id;

  return v_id;
end $$;
```

예외 이름을 코드 문자열로 던지는 이유는 클라이언트가 사유별로 다른 안내를 띄워야 하기 때문이다.
낙관적 업데이트를 롤백할 때 이유를 안 보여주면 유저는 제보가 조용히 사라진 것으로 받아들인다(ADR-0003).

제한이 느슨한 이유와 "수명 연장" 분기의 근거는 ADR-0006에 있다. 요약하면, 도배를 막는 것은 rate limit이
아니라 `count(distinct user_id)` 집계이며, 제한을 조이면 막히는 쪽은 어뷰징이 아니라 급변하는 날씨를
따라가는 정상 제보다.

### vote_report

```sql
create or replace function vote_report(
  p_report_id uuid,
  p_vote      vote_kind,
  p_lat       double precision,
  p_lng       double precision,
  p_is_mocked boolean default false
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_voter geography := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
  v_report reports%rowtype;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_is_mocked then raise exception 'MOCK_LOCATION'; end if;

  select * into v_report from reports where id = p_report_id;
  if not found                     then raise exception 'NOT_FOUND'; end if;
  if v_report.expires_at <= now()  then raise exception 'EXPIRED';   end if;
  if v_report.user_id = v_user     then raise exception 'OWN_REPORT'; end if;

  -- 제보 위치 근처에 있는 사람의 투표만 유효하다
  if st_distance(v_report.cell_point, v_voter) > 2000 then
    raise exception 'TOO_FAR';
  end if;

  insert into report_votes (report_id, user_id, vote, raw_point)
  values (p_report_id, v_user, p_vote, v_voter)
  on conflict (report_id, user_id) do update
    set vote = excluded.vote, created_at = now();
end $$;
```

### nearby_summary — 메인 카드용 적응형 반경 집계

```sql
create or replace function nearby_summary(
  p_lat double precision,
  p_lng double precision
) returns table (
  used_radius_m  int,
  state          weather_state,
  reporter_count int,
  confirm_count  int,
  dispute_count  int,
  nearest_m      int,
  latest_at      timestamptz
)
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me geography := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
  v_r  int;
begin
  foreach v_r in array array[2000, 4000, 6000, 10000] loop
    return query
    with live as (
      select r.* from reports r
      where r.expires_at > now()
        and st_dwithin(r.cell_point, v_me, v_r)
    )
    select v_r,
           l.state,
           count(distinct l.user_id)::int,
           count(distinct v.user_id) filter (where v.vote = 'confirm')::int,
           count(distinct v.user_id) filter (where v.vote = 'dispute')::int,
           min(st_distance(l.cell_point, v_me))::int,
           max(l.observed_at)
    from live l
    left join report_votes v on v.report_id = l.id
    group by l.state;

    if found then return; end if;
  end loop;
end $$;
```

가까운 반경부터 시도해서 결과가 나오는 첫 반경에서 멈춘다. `used_radius_m`을 같이 반환하는 이유는
UI가 "6km 밖 제보 2건"처럼 거리를 밝혀야 하기 때문이다 — 넓혀서 찾았다는 사실을 숨기면 유저가 신뢰도를
잘못 판단한다.

`count(distinct user_id)`가 중요하다. 한 유저가 여러 번 제보해도 합의 강도는 1이다.

상태별로 행을 나눠 반환하고 하나로 뭉치지 않는다. 엇갈림을 다수결로 덮으면 "여기 날씨가 갈리고 있다"는
정보가 사라지는데, 그게 이 앱이 유일하게 알려줄 수 있는 것이다.

### reports_in_bounds — 지도 뷰포트 조회

```sql
create or replace function reports_in_bounds(
  p_min_lat double precision, p_min_lng double precision,
  p_max_lat double precision, p_max_lng double precision,
  p_limit   int default 500
) returns table (
  cell_id        text,
  lat            double precision,
  lng            double precision,
  state          weather_state,
  reporter_count int,
  latest_at      timestamptz
)
language sql security definer set search_path = public, pg_temp as $$
  select r.cell_id,
         st_y(r.cell_point::geometry),
         st_x(r.cell_point::geometry),
         r.state,
         count(distinct r.user_id)::int,
         max(r.observed_at)
  from reports r
  where r.expires_at > now()
    and st_intersects(
          r.cell_point,
          st_makeenvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326)::geography)
  group by r.cell_id, r.cell_point, r.state
  order by max(r.observed_at) desc
  limit least(p_limit, 500);
$$;
```

격자 단위로 집계해서 반환하므로 핀 개수가 제보 수가 아니라 격자 수에 비례한다. 서울 도심에서 제보가
폭증해도 클라이언트가 받는 데이터량은 완만하게 는다.

상한 500은 임의값이며, 넘칠 경우 조용히 잘리는 대신 UI에서 "더 확대하세요"를 띄워야 한다.

**미결**: 제보자가 1명뿐인 격자를 숨길지 여부(ADR-0002). 숨기면 프라이버시가 올라가지만 초기의 빈 지도가
더 비어 보인다.

### 나머지 RPC

- `upsert_watched_area(label, lat, lng)` / `delete_watched_area(id)` — 계정당 최대 3개 제한
- `register_push_token(token)` — `profiles.push_token` 갱신
- `flag_report(report_id, reason)`

## 권한

```sql
alter table profiles                enable row level security;
alter table reports                 enable row level security;
alter table report_votes            enable row level security;
alter table report_flags            enable row level security;
alter table watched_areas           enable row level security;
alter table alert_sends             enable row level security;
alter table kma_observations        enable row level security;
alter table weather_state_lifespans enable row level security;
-- 정책을 만들지 않는다 = 전면 거부

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated;

grant execute on function
  submit_report, vote_report, flag_report,
  nearby_summary, reports_in_bounds,
  upsert_watched_area, delete_watched_area, register_push_token
to authenticated;
```

익명 인증으로 로그인한 유저도 `authenticated` 롤을 받는다. `anon` 롤은 로그인 이전 상태이므로 아무
권한도 주지 않는다.

## 배치 작업

```sql
-- 원좌표 폐기 (ADR-0002)
select cron.schedule('purge-raw-coords', '7 * * * *', $$
  update reports      set raw_point = null
   where raw_point is not null and created_at < now() - interval '24 hours';
  update report_votes set raw_point = null
   where raw_point is not null and created_at < now() - interval '24 hours';
$$);

-- 불일치 알림 (ADR-0005)
select cron.schedule('divergence-alerts', '*/5 * * * *', $$ select check_divergence_alerts(); $$);
```

`check_divergence_alerts()`가 하는 일:

1. 각 `watched_areas` 행에 대해 해당 격자 주변의 최근 30분 강수 제보(`rain`/`snow`)를 세되, 서로 다른
   `user_id`가 2명 이상인 것만 남긴다
2. 같은 `kma_nx/ny`의 최신 `kma_observations`를 조회해 `pty = 0`(강수 없음)인 경우만 남긴다
3. `alert_sends`에서 해당 관심 지역의 최근 발송이 3시간 이내면 제외한다
4. 남은 대상에 Expo Push API로 발송하고 `alert_sends`에 기록한다

실황 캐시가 낡았으면(예: 90분 이상) 발송하지 않는다. 기상청 데이터를 모르는 상태에서는 "어긋났다"는
판정 자체가 불가능하기 때문이다.
