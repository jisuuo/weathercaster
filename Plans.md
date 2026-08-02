---
_harness_template: "Plans.md.template"
_harness_version: "4.3.3"
---

# Plans.md - Task Tracking

> **Project**: weathercaster
> **Last updated**: 2026-08-02
> **Updated by**: Claude Code
> **Purpose**: 유저 날씨 제보와 기상청 실황을 나란히 놓아 "공식 관측이 놓친 지금 여기 날씨"를 드러내는 앱의 MVP를 완성한다.

관련 문서: `CONTEXT.md`(용어) · `docs/data-model.md`(서버 SQL 전문) · `docs/screens.md`(화면) · `docs/adr/`(결정 근거)

---

## 시작 상태 (2026-08-02)

설계 문서는 완성돼 있고 **코드는 0줄**이다. `package.json` / `App.tsx` / `app.json` / `assets/` / `supabase/` 전부 없으며 git 에도 없어 복구 불가. 따라서 이 계획은 백지 설계가 아니라 **`docs/data-model.md` 의 SQL 을 옮겨 적고 테스트를 붙이는 일**에 가깝다.

미확인: 이 컴퓨터의 Docker 설치 여부(로컬 Supabase 전제). 모른다 ≠ 없다. T3 에서 확인된다.

외부 계정/키(Supabase·기상청·네이버) 전부 미보유 → T12·T17·T24 에 발급 태스크로 포함.

---

## In Progress

<!-- Add tasks with cc:wip here. -->

(none)

---

## Not Started

### Phase 0 — 준비물

| Task | 내용 | DoD | Depends | Status |
|---|---|---|---|---|
| T1 | 앱 스캐폴드 `[lane:fast][tdd:skip:scaffold]` — Expo `blank-typescript`(expo-router 없음), deps `@supabase/supabase-js`·`expo-location`·`expo-secure-store`·`react-native-url-polyfill`, `app.json`(앱 이름·번들 ID·한국어 위치 권한 문구), `.gitignore` | 실기기/시뮬레이터에서 앱이 뜬다 | - | `cc:done` |
| T2 | 검사 도구 `[lane:fast][tdd:skip:tooling]` — eslint(expo)+prettier, `jest-expo`+`@testing-library/react-native`, npm scripts `lint`/`test` | `npm run lint` 와 `npm test` 둘 다 exit 0 | T1 | `cc:todo` |
| T3 | 로컬 Supabase `[lane:fast][tdd:skip:tooling]` — `supabase` CLI devDep, `supabase init` / `supabase start` | `supabase status` 가 주소 목록 출력 | T1 | `cc:todo` |

**중간 상태**
- T1 끝 → 흰 화면 앱이 뜬다. 제보·지도·서버 연결 전부 안 됨
- T2 끝 → 검사 명령이 돈다. 검사할 코드는 아직 없음(빈 통과)
- T3 끝 → 로컬 DB 접속 가능. 테이블 0개. **Docker 없으면 여기서 막힌다**

**함정(겪음)**: `create-expo-app` 은 폴더에 `CONTEXT.md` 가 있으면 실행을 거부한다 → 임시 디렉토리에 만든 뒤 앱 파일만 복사. 템플릿이 딸려 만드는 `CLAUDE.md`/`AGENTS.md`/`LICENSE`/`.git` 은 **복사 금지**(하네스 `CLAUDE.md` 를 덮어쓴다).

---

### Phase 1 — 서버 코어 (로컬, 외부 키 불필요)

| Task | 내용 | DoD | Depends | Status |
|---|---|---|---|---|
| T4 | `0001_schema.sql` `[lane:gate][tdd:required]` — enum 3종(`weather_state` 9값/`vote_kind`/`flag_reason`), 테이블 8개(profiles, weather_state_lifespans, reports, report_votes, report_flags, watched_areas, alert_sends, kma_observations), 인덱스 5종, `auth.users`→`profiles` 트리거. postgis·btree_gist·pg_cron 은 `extensions` 스키마 | `supabase db reset` 무에러 + `weather_state_lifespans` 정확히 9행 | T3 | `cc:todo` |
| T5 | `0002_functions.sql` `[tdd:required]` — `snap_to_cell`(EPSG:5179, 100m 격자 중심), `kma_grid`(LCC 변환), `report_lifespan` + `tests/functions.test.sql` | pgTAP 5건 pass. 서울시청(37.5665,126.9780) → `nx=60,ny=127`, 스냅 오차 ≤71m | T4 | `cc:todo` |
| T6 | `0003_rpc.sql` `[tdd:required]` — `submit_report`(검사 7단계 + 같은 격자·같은 상태 재제보 시 수명 연장), `nearby_summary`(적응형 반경 2/4/6/10km, `used_radius_m` 반환) + `tests/submit_report.test.sql` | pgTAP 10건 pass. `TOO_SOON`·`DAILY_LIMIT`·`LOW_ACCURACY`·`MOCK_LOCATION`·`IMPOSSIBLE_SPEED`·`BANNED` 각각 raise + 재제보 시 행 수 불변 | T5 | `cc:todo` |
| T7 | `0004_grants.sql` `[lane:gate][tdd:required]` — 전 테이블 RLS 활성화(정책 없음 = 전면 거부), anon/authenticated 권한 회수, `alter default privileges`, RPC 에만 execute + `tests/rls.test.sql` | 테이블 직접 select/insert → `42501`, RPC → 통과, `nearby_summary` 반환 타입에 `raw_point` 없음 | T6 | `cc:todo` |

**중간 상태**
- T4 끝 → 제보를 담을 그릇 완성. 손으로 SQL 넣고 뺄 수 있음. 앱은 아직 연결 없음
- T5 끝 → 좌표 → 격자 / 기상청 격자번호 변환 동작. **개인정보 보호의 핵심 부품 완성**
- T6 끝 → 서버 기능 사실상 완성. **단 아직 문이 안 잠겨 원좌표가 노출 가능한 상태**
- T7 끝 → RPC 창구로만 접근 가능. 원좌표가 밖으로 나갈 경로 소멸

**함정(겪음)**
- 제보 전후 카운트를 CTE 하나에 넣지 말 것. CTE 는 같은 스냅샷을 보므로 "제보 후" 값이 제보를 반영하지 않는다 → 임시 테이블로 문장 분리
- `count(*)` 는 `bigint`. pgTAP `is()` 에 넘기려면 `::int` 캐스팅
- pgTAP LIKE 비교 함수는 `alike`/`unalike`. `like`/`unlike` 는 없다

---

### Phase 2 — 클라이언트 수직 슬라이스 (★ T11 에서 멈춰도 제품)

| Task | 내용 | DoD | Depends | Status |
|---|---|---|---|---|
| T8 | `src/lib/supabase.ts` `[tdd:required]` — SecureStore 세션 어댑터, 앱 시작 시 세션 없으면 `signInAnonymously()`. 로그인 UI 노출 0 | 첫 실행 후 `auth.users`·`profiles` 각 1행, 앱 재시작 후 `user_id` 동일 | T7 | `cc:todo` |
| T9 | 위치 + 권한 흐름 `[tdd:required]` — 홈 진입 즉시 GPS 선확보, 권한 요청은 **제보 버튼 첫 탭 시점**(첫 실행 시 안 물음) | 권한 거부 시 앱 생존 + "설정에서 켜기" 안내 + 시트 안 열림 | T8 | `cc:todo` |
| T10 | 홈 카드 `[tdd:required]` — `nearby_summary` 연결, 상태 6종(권한없음/확보중/0건/있음/넓혀찾음/엇갈림), 넓혀 찾으면 거리 밝힘, 엇갈림은 다수결 금지·상위 2개+"외 N건". 상단 기상청 블록은 자리만 | 6개 상태 각각 렌더 테스트 pass | T9 | `cc:todo` |
| T11 | 제보 시트 `[tdd:required]` — 2행 3열 6칸, **1탭 즉시 제출·확인 버튼 없음**, "기타"는 2차 시트(우박/강풍/안개/황사), 4초 "제보했어요·취소" 스낵바, 낙관적 업데이트 + 실패 시 롤백 **및 사유 표시**(조용한 롤백 금지) | 서버 예외 6종 → 화면 문구 매핑 유닛 테스트 pass + 실기기 앱 실행부터 제보 완료까지 5초 이내 | T10 | `cc:todo` |

**중간 상태**
- T8 끝 → 앱이 서버에 신원을 말할 수 있음. 화면은 여전히 백지
- T9 끝 → 위치 확보, 권한 거부해도 앱 생존. 보여줄 화면 없음
- T10 끝 → 근처 제보가 보임. **내가 제보는 못 함.** 상단 기상청 칸 비어 있음
- T11 끝 → ★ **앱이 제품으로 굴러감.** 아직 안 되는 것: 기상청 비교, 지도, 알림, 투표

**T11 실패 문구 매핑**: `TOO_SOON` "방금 제보하셨어요. 잠시 후 다시 시도해주세요" / `DAILY_LIMIT` "오늘 제보는 여기까지예요" / `LOW_ACCURACY` "위치가 정확하지 않아요. 실외에서 다시 시도해주세요" / `MOCK_LOCATION`·`IMPOSSIBLE_SPEED` "위치를 확인할 수 없어요"(같은 문구로 묶는 것은 의도적 — 어뷰저에게 검사 항목을 알리지 않는다) / `BANNED` "제보가 제한된 계정이에요" / 네트워크 오류 "전송 실패(재시도)"

---

### Phase 3 — 기상청 실황

| Task | 내용 | DoD | Depends | Status |
|---|---|---|---|---|
| T12 | 기상청 API 키 발급 `[사용자 작업]` — 공공데이터포털 초단기실황 `getUltraSrtNcst` | 발급 키로 curl 200 + JSON 응답 | - | `cc:todo` |
| T13 | 실황 수집 Edge Function `[tdd:required]` — 대상 격자 실황 fetch → `kma_observations` upsert. **키는 Edge Function secret 전용, 앱 번들 금지**. `docs/data-model.md` 에 수집 계약(주기·격자 선정) 추가 | 로컬 invoke 후 `kma_observations` 행 생성 + 앱 번들에서 키 문자열 grep 0건 | T12, T7 | `cc:todo` |
| T14 | 수집 cron + 홈 상단 블록 — 갱신 스케줄 등록, 홈에 **상태 + 관측 시각 필수 표시** | 홈에 "기상청 · 14시 관측" 형태로 시각 노출, 90분 초과 시 낡음 표시 | T13, T11 | `cc:todo` |

**중간 상태**
- T12 끝 → 데이터 받을 자격만 생김. 코드 없음
- T13 끝 → DB 에 실황이 쌓임. 자동 실행 아님(수동 호출), 화면에 안 나옴
- T14 끝 → ★ **앱의 핵심 주장이 화면에 나타남** — 위는 공식, 아래는 현장. 지도·투표·알림은 아직

관측 시각 표기가 필수인 이유: 초단기실황은 40~100분 지난 값이다(ADR-0006). "지금"인 척 보여주면 이 앱이 왜 필요한지 유저가 영영 모른다.

---

### Phase 4 — 지도 · 투표

| Task | 내용 | DoD | Depends | Status |
|---|---|---|---|---|
| T15 | 미결 2건 결정 + 문서 갱신 `[lane:gate]` — ① 저밀도 격자: 제보자 2명 미만 격자는 지도에서 숨김, **단 내 제보는 1명이어도 나에게는 보임** ② 권한 거부 시 홈 기본 지역: 마지막으로 본 지역, 없으면 서울시청 | ADR-0002 "미결" 문단이 결정으로 교체 + `docs/screens.md` 미결 목록에서 제거 | - | `cc:todo` |
| T16 | 지도·투표 RPC `[tdd:required]` — `reports_in_bounds`(격자 집계, limit 500, T15 저밀도 필터 반영), `vote_report`(2km 이내만·본인 제보 불가·만료 불가), `flag_report` + pgTAP | 2km 밖 → `TOO_FAR`, 본인 제보 → `OWN_REPORT`, 만료 → `EXPIRED`, 500 상한 동작 | T15, T7 | `cc:todo` |
| T17 | 네이버 지도 ID 발급 + dev build `[사용자 작업 포함]` — Mobile Dynamic Map 클라이언트 ID, EAS development build, config plugin | 실기기 dev build 에서 지도 타일 렌더 | T1 | `cc:todo` |
| T18 | 지도 탭 `[tdd:required]` — SDK 는 어댑터 1파일로 감쌈, 핀 = 격자 1칸 + 제보자 수 뱃지, 뷰포트 재조회 디바운스 400ms, 500건 도달 시 토스트, 수명 지난 제보는 투명도 40% 로 잔존, 하단 실황 고정 바 | 뷰포트 이동 시 400ms 디바운스 확인 + 500건 토스트 노출 | T16, T17, T14 | `cc:todo` |
| T19 | 제보 상세 시트 `[tdd:required]` — "여기 지금 비 와요?" 질문형 + [맞아요][아니에요], 격자 반경 2km 밖이면 비활성 + 안내, 본인 제보는 버튼 미노출, 신고 3종 | 반경 밖 비활성 + 문구 노출, 본인 제보 버튼 없음 | T18 | `cc:todo` |

**중간 상태**
- T15 끝 → 코드 변화 0. T16/T18 이 만들 것이 확정됨
- T16 끝 → 서버가 지도 데이터·투표 처리 가능. 보여줄 화면 없음
- T17 끝 → 내 폰에 설치본 + 지도 타일. 제보 핀은 없음
- T18 끝 → "우리 동네 어디에 비 오나"가 눈에 보임. 핀 눌러도 상세 안 뜸
- T19 끝 → 유저끼리 검증 시작. **앱을 안 열면 여전히 아무 일도 안 일어남**

---

### Phase 5 — 관심 지역 · 알림

| Task | 내용 | DoD | Depends | Status |
|---|---|---|---|---|
| T20 | 관심 지역·푸시 RPC `[tdd:required]` — `upsert_watched_area`(계정당 최대 3), `delete_watched_area`, `register_push_token` + pgTAP | 4번째 등록 시 예외, 같은 label 재등록은 갱신 | T7 | `cc:todo` |
| T21 | 설정 화면 `[tdd:required]` — 홈 우상단 아이콘(탭 아님), 알림 토글, 관심 지역 편집(**지도에서 찍기, 주소 검색 없음**), 개인정보처리방침/문의, 앱 버전, Expo push token 등록 | 실기기에서 push token 이 `profiles.push_token` 에 저장됨 | T20, T18 | `cc:todo` |
| T22 | 불일치 알림 `[tdd:required]` — `check_divergence_alerts()`: ①최근 30분 내 서로 다른 유저 강수 제보 2건↑ ②같은 nx/ny 최신 실황 `pty=0` ③3시간 쿨다운 ④실황이 90분 이내. Expo Push 발송 + `alert_sends` 기록. cron `*/5 * * * *` | 4개 조건 각각 pgTAP 검증 + 실기기 1회 실제 수신 | T21, T14 | `cc:todo` |
| T23 | 원좌표 폐기 cron `[tdd:required]` — `purge-raw-coords` 매시 7분, 24시간 경과 `reports`/`report_votes` 의 `raw_point` NULL | 25시간 전 데이터 주입 후 job 실행 → `raw_point` 전부 NULL | T7 | `cc:todo` |

**중간 상태**
- T20 끝 → "집"·"회사" 등록 가능. 등록할 화면이 없음
- T21 끝 → 관심 지역 등록·알림 토글 가능. **켜도 알림은 안 옴**(보내는 쪽 없음)
- T22 끝 → ★ **앱을 안 열어도 가치가 전달됨.** 아직 로컬 환경에서만 동작
- T23 끝 → 개인정보 약속(ADR-0002)이 코드로 지켜짐

---

### Phase 6 — 원격 배포 · 출시

| Task | 내용 | DoD | Depends | Status |
|---|---|---|---|---|
| T24 | 원격 Supabase `[lane:release][사용자 작업 포함]` — 프로젝트 생성, `supabase link`, `db push`, Edge Function 배포 + secret 설정 | 원격에서 `rls.test.sql` 동등 검증 pass | T23, T22 | `cc:todo` |
| T25 | 실기기 종단 검증 `[lane:release]` — `docs/screens.md` 5개 시나리오: 5초 이내 제보 / 즉시 반영 / `TOO_SOON` 문구 / 기내 모드 재시도 / 권한 거부 시 앱 생존 | 5개 시나리오 결과 기록, 실패 0건 | T24 | `cc:todo` |
| T26 | 스토어 제출 준비 `[lane:release]` — UGC 요건(신고·차단 수단 증빙), 개인정보처리방침 URL, 아이콘·스크린샷, EAS production build | TestFlight / Play 내부 테스트 업로드 성공 | T25 | `cc:todo` |

**중간 상태**
- T24 끝 → 내 컴퓨터를 꺼도 앱이 돔. 다른 사람이 쓸 수 있음. 스토어에는 없음
- T25 끝 → 실기기에서 실제 동작 확인 완료
- T26 끝 → 심사 제출 가능

---

## 실행 순서

```
T1 ─┬─ T2
    └─ T3 ─ T4 ─ T5 ─ T6 ─ T7 ─ T8 ─ T9 ─ T10 ─ T11  ★ 앱이 굴러감
                                                    │
T12(지금 신청) ────────────────── T13 ─ T14 ────────┤  ★ 비교가 생김
T15(지금 가능) ─ T16 ─┐                             │
T17(지금 신청) ───────┴─ T18 ─ T19 ─────────────────┤
                        T20 ─ T21 ─ T22             │  ★ 알림
                        T23                         │
                                    T24 ─ T25 ─ T26 ┘
```

외부 키가 하나도 없어도 **T1~T11 + T15 + T20 + T23 은 로컬만으로 완주 가능**. T12(기상청)·T17(네이버) 발급은 지금 병행 신청하면 Phase 3~4 에서 대기하지 않는다.

---

## 계획에서 제외 (Reject)

| 제외 | 근거 |
|---|---|
| 주소 검색 API | 비용·의존성 증가, 등록처는 집·회사 둘뿐 (`docs/screens.md`) |
| 온보딩/튜토리얼/로그인 화면 | 홈 화면 자체가 설명 (`docs/screens.md`) |
| 다수결 단일 상태 요약 | 엇갈림이 이 앱의 유일한 고유 정보 (`CONTEXT.md`) |
| 백그라운드 위치 추적 | iOS Always 권한 + 배터리 + 원좌표 24시간 정책과 충돌 (ADR-0005) |
| 좋아요 / 랭킹 / 신뢰도 점수 | `CONTEXT.md` 금지어 |
| 3번째 탭 | "하단 탭 2개. 그 이상은 없다" (`docs/screens.md`) |
| App Attest / Play Integrity | 실제 어뷰징 관측 후가 순서 (ADR-0003) |

26건을 줄이지 않은 이유: 자를 후보(지도/알림)가 각각 ADR 하나씩을 통째로 무효화한다. 대신 T11 에서 멈춰도 제품이 되도록 순서를 짰다.

---

## Spec delta

`spec.md` 는 새로 만들지 않는다. 이 저장소는 `CONTEXT.md`(용어) + `docs/data-model.md`(서버 계약) + `docs/screens.md`(화면 계약) + `docs/adr/`(결정) 로 product contract 를 나눠 갖고 있고 그 규약을 따른다. 채워야 할 빈칸 2개:

1. `docs/data-model.md` — `kma_observations` 를 **누가 어떤 주기로 채우는지** 계약이 없다 → T13 에서 추가
2. `docs/screens.md` + `docs/adr/0002` — 미결 2건 → T15 에서 결정으로 교체

---

## 사전 확인 (계획 승인 시 일괄)

```text
- 사항: 로컬 DB 초기화 (`supabase db reset`) — 로컬 데이터 전량 삭제
  이유: T4~T7 마이그레이션·pgTAP 검증마다 필요
  scope: Phase 1 / T4,T5,T6,T7

- 사항: `.env` 읽기 — 기상청 키, 네이버 클라이언트 ID, Supabase 키
  이유: Edge Function secret 및 앱 설정 주입 경로 확인
  scope: Phase 3 / T13, Phase 4 / T17, Phase 6 / T24

- 사항: 외부 API 호출 — 기상청 `getUltraSrtNcst`, Expo Push API, 네이버 지도 타일
  이유: T13·T17·T22 의 DoD 가 실제 응답과 실기기 수신을 요구
  scope: Phase 3 / T13, Phase 4 / T17, Phase 5 / T22

- 사항: 원격 반영 — `supabase link` / `db push` / Edge Function deploy / EAS build 제출
  이유: T24·T26 의 DoD 가 원격 환경 검증을 요구
  scope: Phase 6 / T24,T26

- 사항: `git push`
  이유: Phase 종료 시 작업 보존
  scope: 전 Phase
```

`.env` 읽기 승인은 값 출력 허가가 아니다. 필요한 path 만 열고 값은 화면에 뿌리지 않는다.

---

## 검증 방법

- 서버: `supabase db reset && supabase test db` — pgTAP 전량(T5 5건, T6 10건, T7 5건, T16·T20·T22·T23 추가분)
- 클라이언트: `npm test` — 홈 상태 6종, 실패 문구 6종, 디바운스, 낙관적 롤백
- 스타일: `npm run lint`
- 종단: T25 실기기 5개 시나리오(자동화 불가, 수동 기록)
- 보안: 테이블 직접 접근 `42501` + 앱 번들 API 키 grep 0건

---

## 검증 이력 (team_validation_mode: manual-pass)

서브에이전트 미사용(세션 지시). 5개 관점 단독 점검:

- **Product** — Phase 2(제보)가 Phase 3(실황)보다 앞선다. 의도적이다. 미검증 가정 3개(100m 격자 변환, 테이블 전면 차단, 무화면 익명 인증)가 전부 제보 경로에 있고, 실황은 외부 키 발급에 막혀 있다
- **Architecture** — 서버 SQL 원문이 문서에 있어 T4~T7 은 설계가 아니라 이식. 지도 SDK 는 어댑터 1파일로 격리(ADR-0004)
- **Security** — 원좌표는 RPC 밖으로 나갈 경로가 없다(T7 의 반환 타입 검사). 기상청 키는 Edge Function secret 전용 + 번들 grep 검사(T13). 모든 `SECURITY DEFINER` 함수에 `search_path` 고정
- **QA** — 서버 pgTAP, 클라이언트 jest. 5초 예산과 실기기 시나리오는 자동화 불가라 T25 수동 기록
- **Skeptic** — 1인 MVP 로 26건은 크다. 그래도 자르지 않은 이유는 Reject 표에. 대신 T11 이 안전 정지점

---

## Completed

<!-- Add tasks with cc:done or pm:approved here. -->

(none)

---

## Archive

<!-- Move older completed tasks here. -->

---

## Status Marker Legend

| Marker | Meaning |
|--------|---------|
| `pm:requested` | PM requested work |
| `cc:todo` | Not started by Claude Code |
| `cc:wip` | Claude Code is working |
| `cc:done` | Claude Code completed the task and is awaiting confirmation |
| `pm:approved` | PM confirmed completion |
| `blocked` | Blocked; include the reason next to the task |

---

## Last Update

- **Updated at**: 2026-08-02
- **Last session owner**: Claude Code
- **Branch**: main
