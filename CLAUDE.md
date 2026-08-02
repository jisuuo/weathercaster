---
_harness_template: "CLAUDE.md.template"
_harness_version: "4.3.3"
---

# CLAUDE.md - Claude Code Instructions

> **Project**: weathercaster
> **Created**: 2026-08-02
> **Setup locale**: ko

---

## Read This First

- `CONTEXT.md` — 도메인 언어(제보/실황/예보/수명/엇갈림)와 제품의 존재 이유. 용어는 여기 정의를 따른다.
- `docs/data-model.md`, `docs/screens.md`, `docs/adr/` — 데이터 모델, 화면, 결정 기록.
- `Plans.md` — 작업 추적. 상태 마커는 Plans.md 범례를 따른다.

---

## 1. Stack

- Expo (SDK 57) + React Native 0.86 + React 19, TypeScript
- Supabase (`@supabase/supabase-js`), 마이그레이션은 `supabase/`
- `expo-location`(GPS 좌표), `expo-secure-store`(토큰)

```bash
npm start          # expo start
npm run ios        # iOS 시뮬레이터
npm run android    # Android
```

---

## 2. Scope

### Work You Own

- Plans.md 에 있는 작업 구현, 커밋, 푸시
- CI 실패 시 최대 3회 자동 수정 시도

### Work You Must Not Do

- 요청 범위 밖 리팩터링
- Supabase 프로덕션 데이터/설정 변경
- 명시 요청 없는 보안 설정 변경

---

## 3. Commit Message Convention

```text
feat: add a new feature
fix: fix a bug
docs: update documentation
refactor: refactor code
test: add or update tests
chore: maintenance work
```

Example: `feat: add weather report submission`

---

## 4. CI Failure Handling

1. CI 실패 감지 → 에러 로그 확인
2. 수정 → 커밋 → CI 재실행
3. 3회 실패하면 중단하고 원인 가설 + 시도한 수정 목록을 보고

---

## 5. Session Routine

### At Session Start

```bash
git status -sb
cat Plans.md
```

### At Completion

```bash
git add -A
git commit -m "feat: [change summary]"
git push
```

---

## 6. Available Commands

| Command | Purpose |
|---------|---------|
| `/harness-sync` | 상태 확인, 다음 액션 제안 |
| `/harness-work` | 작업 실행, Plans.md 갱신 |
| `/harness-review` | 품질 리뷰 |

---

## 7. Troubleshooting

| Symptom | Action |
|---------|--------|
| 작업을 못 찾음 | `Plans.md` 확인 후 사용자에게 질문 |
| CI 반복 실패 | 3회 시도 후 에스컬레이션 |
| 범위가 불명확 | 구현 전에 질문 |
