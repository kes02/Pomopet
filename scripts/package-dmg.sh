#!/usr/bin/env bash
# Pomopet 릴리스 .app 빌드 → ad-hoc 서명 → .dmg 패키징.
# 사용법: scripts/package-dmg.sh <version>   (예: scripts/package-dmg.sh 1.0.0)
# 결과: dist/Pomopet-<version>.dmg  (+ sha256 출력)
#
# 미서명(공증 없음) 빌드입니다. 받는 사람은 첫 실행 시 Gatekeeper 경고를
# 우클릭→열기 또는  xattr -dr com.apple.quarantine /Applications/Pomopet.app  로 우회합니다.
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "사용법: $0 <version>   (예: $0 1.0.0)" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Pomopet"
BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
DIST="$ROOT/dist"
STAGE="$BUILD_DIR/dmg-stage"
DMG_PATH="$DIST/${APP_NAME}-${VERSION}.dmg"

echo "▶︎ Release 빌드…"
rm -rf "$DERIVED" "$STAGE"
mkdir -p "$DIST"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  build | tail -1

APP_PATH="$DERIVED/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "빌드 산출물을 찾지 못했습니다: $APP_PATH" >&2
  exit 1
fi

echo "▶︎ ad-hoc 재서명…"
codesign --deep --force --sign - "$APP_PATH"

echo "▶︎ DMG 스테이징…"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "▶︎ DMG 생성…"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null

SHA="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
echo ""
echo "✅ 완료: $DMG_PATH"
echo "   sha256: $SHA"

# release.sh가 파싱할 수 있도록 마지막 줄에 표준 형식으로 출력
echo "SHA256=$SHA"
