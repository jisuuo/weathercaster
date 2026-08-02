-- 로컬 개발/테스트 전용. `supabase db reset` 이 마이그레이션 뒤에 실행하며,
-- `supabase db push` 는 이 파일을 원격에 보내지 않는다.
--
-- pgTAP 을 마이그레이션이 아니라 여기에 두는 이유: 테스트 도구는 제품 스키마가 아니다.
-- 마이그레이션에 넣으면 원격 프로덕션 DB 에도 영구 설치된다.
create extension if not exists pgtap with schema extensions;
