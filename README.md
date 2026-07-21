# MathLand

MathLand는 `SeoaQuiz`를 Godot 4로 완전히 다시 설계한, 세로 화면 중심의 어린이 수학 탐험 게임입니다. 플레이는 인터넷 없이도 이어지고, 연결된 환경에서는 보호자가 웹에서 학습 흐름을 확인하고 난이도 콘텐츠를 관리할 수 있습니다.

보호자용 공개 데모: <https://jinhoofkepco.github.io/Mathland_new2/>

## 포함된 경험

- 4자리 PIN으로 분리되는 여러 아이 프로필과 프로필별 진도·설정·보상
- 탐험 섬, 오늘의 길, 자유 탐험, 인벤토리, 수집책, 설정 화면
- 오답 시 하트 감소, 하트 0에서 런 종료, 콤보·보스·사과 보상
- 터치 압축·스프링 복귀·햅틱·효과음·파티클을 결합한 버튼 피드백
- 덧셈, 뺄셈, 곱셈, 최소공배수, 소인수분해와 6개 기초수학 활동
- 10틀, 10막대/십진 블록, 수직선, 수 모으기 등 재사용 가능한 보조자료
- 기본값이 꺼진 선택형 적응 난이도와 JSON 기반 난이도/보상/효과 조절
- 문제 중 자동 음성 없이, 스피커 버튼으로만 즉시 재생·중단 가능한 한국어 음성
- 중단 후 같은 문제로 복구되는 체크포인트와 append-only 학습 이벤트 저장
- 보호자 대시보드, 기기 연결, 수동 편집·검증·게시·롤백이 가능한 Content Studio

## 실행 환경

- Godot `4.7.1.stable.official.a13da4feb`
- Compatibility 렌더러
- Node.js 24와 npm workspaces
- Android 빌드는 JDK 17, SDK 35, ARM64 도구체인 사용

macOS 예시는 Godot 경로를 `/opt/homebrew/bin/godot`으로 가정합니다.

```bash
/opt/homebrew/bin/godot --editor --path .
/opt/homebrew/bin/godot --path .
```

프로필을 만들고 PIN을 입력한 뒤 **자유 탐험**에서 11개 활동을 선택할 수 있습니다. 클라우드 설정이 없어도 모든 번들 활동과 로컬 저장은 정상 동작합니다.

## 현장 난이도 수정

원본은 `content/sources/*.json`, 앱이 사용하는 검증 완료 패키지는 `content/packages/`, 활성 목록은 `content/active-manifest.json`입니다.

```bash
npm ci
npm run build:content
npm run validate:content
```

게임 규칙, 난이도 밴드, 문제 생성 범위, 하트, 목표 점수, 보상, 효과, 적응 난이도 허용 범위가 데이터에 들어 있습니다. Content Studio의 샘플 미리보기와 독립 정답 검증을 통과해야 게시할 수 있으며, AI 제안은 자동 게시되지 않고 구조화된 초안으로만 적용됩니다.

## 보호자 웹과 클라우드

GitHub Pages는 실제 아이 데이터나 비밀키를 포함하지 않는 합성 데모 모드로 배포됩니다. 운영 원격 확인에는 별도의 Supabase 프로젝트 배포와 공개 URL/publishable key 설정이 필요합니다. 서비스 역할 키와 refresh token은 브라우저 번들·Godot 리소스·Git 저장소에 넣지 않습니다.

Android 빌드용 공개 설정은 다음 환경변수를 함께 제공했을 때 격리된 staging 디렉터리에만 생성됩니다.

```bash
MATHLAND_SUPABASE_URL=https://PROJECT.supabase.co \
MATHLAND_SUPABASE_PUBLISHABLE_KEY=sb_publishable_EXAMPLE \
bash scripts/android/export_debug.sh
```

값을 생략하면 APK는 안전하게 오프라인 모드로 시작합니다. 공개 설정 예시는 `resources/config/cloud_public.example.json`에 있습니다.

## 검증

```bash
tools/test/run_godot_tests.sh all
npm run test:contracts -- --run
npm run test:web -- --run
npm run typecheck
VITE_MATHLAND_CLOUD_MODE=fake npm run test:e2e
npm run validate:assets
npm run validate:audio
```

Godot 테스트는 별도 플러그인 없이 unit, scene, integration을 실행합니다. 브라우저 여정은 휴대폰과 세로 태블릿을 각각 검증합니다. Supabase 함수와 PostgreSQL/RLS에는 별도의 Deno·pgTAP 검증이 있습니다.

## Android APK

```bash
bash scripts/android/export_debug.sh
```

출력은 `dist/MathLand-debug-arm64.apk`입니다. 빌드 과정은 패키지 ID `com.jinhoofkepco.mathland`, 버전 `1.0.0`/코드 `1`, min SDK 24, target SDK 35, ARM64 단일 ABI, 백업 비활성화, INTERNET/VIBRATE 이외 권한 부재를 검사합니다.

## 데이터 복구와 보안

아이 데이터는 `user://profiles/<profile_id>/` 아래에 저장됩니다. 이벤트는 화면 진행 전에 먼저 기록되고, 앱 일시정지·Android 뒤로가기 시 현재 런을 체크포인트합니다. 수동 복구 전에는 프로필 디렉터리 전체를 백업하세요.

구조와 복구 경계는 [Godot foundation architecture](docs/architecture/godot-foundation.md), 서비스 권한은 [service-role boundaries](docs/architecture/service-role-boundaries.md), 운영 원칙은 [개인정보 안내](PRIVACY.md)와 [보안 정책](SECURITY.md)에서 설명합니다.
