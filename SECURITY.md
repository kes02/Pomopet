# Security Policy

## 보안 모델 (요약)
Pomopet은 **미서명**(Apple Developer ID 없음) macOS 앱이며 **[Sparkle](https://sparkle-project.org)** 로 자동 업데이트합니다. 따라서 신뢰의 뿌리는 **EdDSA(ed25519) 서명**입니다.

- **업데이트 무결성** — 모든 업데이트(DMG)는 EdDSA로 서명되고, 앱에 내장된 공개키(`Info.plist`의 `SUPublicEDKey`)로 검증됩니다. 서명이 맞지 않으면 설치되지 않습니다. 업데이트 피드(appcast)는 **HTTPS**(GitHub Releases)로만 받습니다.
- **첫 설치 무결성** — DMG는 HTTPS로 배포되며, Homebrew cask가 DMG의 `sha256`을 고정합니다.
- **App Sandbox 미적용** — 자동 설치(Sparkle)를 위해 비활성화되어 있습니다. 미서명 배포본은 어차피 비-sandbox로 실행됩니다.
- 앱은 외부 네트워크 호출이 Sparkle 업데이트 확인뿐이며, 개인정보를 전송하지 않습니다.

## 🔑 서명 개인키 관리 (메인테이너 필독)
EdDSA **개인키가 이 프로젝트의 단일 최중요 비밀**입니다. 유출되면 공격자가 **모든 사용자에게 악성 자동 업데이트**를 보낼 수 있습니다.

- 개인키는 **로그인 Keychain**에만 보관합니다(서비스 `https://sparkle-project.org`). **저장소에 절대 커밋하지 마세요.**
- 백업본(`generate_keys -x`로 export)은 **비밀번호 관리자/암호화 저장소**에만 보관하세요. 평문 파일을 repo·클라우드 동기화 폴더·이메일에 두지 마세요.
- 릴리스는 **신뢰된 머신에서만** 수행하세요(`scripts/release.sh`가 Keychain의 개인키로 서명).
- 공개키(`SUPublicEDKey`)는 공개되어도 안전합니다(앱에 배포되는 값).

## 취약점 제보
보안 취약점은 **공개 이슈로 올리지 말고** 비공개로 알려 주세요:

- GitHub의 **Security → "Report a vulnerability"**(Private Vulnerability Reporting), 또는 메인테이너에게 직접 연락.

가능하면 **재현 절차와 영향 범위**를 포함해 주세요. 확인 후 수정 → 릴리스 → 공개 순으로 처리합니다.

## 지원 버전
최신 릴리스만 보안 업데이트를 받습니다. Sparkle 자동 업데이트로 항상 최신 버전을 유지하세요.
