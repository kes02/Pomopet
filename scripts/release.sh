#!/usr/bin/env bash
# Pomopet 릴리스: DMG 빌드 → GitHub Release 생성/업로드 → Homebrew cask 갱신.
# 사용법: scripts/release.sh <version>   (예: scripts/release.sh 1.0.0)
#
# 필요: gh CLI 로그인(kes02), Homebrew 탭 repo(kes02/homebrew-pomopet) 존재.
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "사용법: $0 <version>   (예: $0 1.0.0)" >&2
  exit 1
fi
# 버전 형식 검증 — VERSION이 appcast XML·cask·태그·파일명에 그대로 들어가므로
# semver(major.minor.patch)만 허용해 이상값/XML·셸 메타문자 주입을 원천 차단.
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "버전 형식 오류: '$VERSION' — 'major.minor.patch' 형식만 허용 (예: 1.2.0)." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Pomopet"
TAG="v${VERSION}"
DMG_PATH="$ROOT/dist/${APP_NAME}-${VERSION}.dmg"
REPO="kes02/Pomopet"
TAP_REPO="kes02/homebrew-pomopet"
RELEASE_BRANCH="main"   # 릴리스 태그가 찍히는 프로덕션 브랜치 (develop → release → main)

# 0) 릴리스 브랜치 확인 — DMG는 현재 작업트리에서 빌드되므로, 태그 대상(main)과 반드시 일치해야 함.
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]]; then
  echo "현재 브랜치가 '$CURRENT_BRANCH' 입니다. 릴리스는 '$RELEASE_BRANCH'에서 실행하세요 (release → main 승격 후)." >&2
  exit 1
fi

# 0.7) CHANGELOG.md에서 이번 버전 릴리스 노트 추출 → GitHub Release 본문 + Sparkle appcast 설명에 사용.
CHANGELOG="$ROOT/CHANGELOG.md"
NOTES_MD="$(awk -v v="$VERSION" '
  $0 ~ ("^## \\[" v "\\]") { grab=1; next }   # "## [1.3.0] - ..." 헤더에서 수집 시작
  grab && /^## \[/ { exit }                    # 다음 버전 헤더에서 중단
  grab { print }
' "$CHANGELOG" 2>/dev/null | sed -e '/./,$!d')"   # 선행 빈 줄 제거
if [[ -z "${NOTES_MD//[[:space:]]/}" ]]; then
  echo "⚠︎ CHANGELOG.md에 '## [$VERSION]' 섹션이 없습니다 — 변경사항 없이 진행." >&2
  NOTES_MD="- 자세한 변경사항은 커밋 로그를 참고하세요."
fi

# GitHub Release 본문: 변경사항(CHANGELOG) + 설치 안내
INSTALL_NOTE="미서명 빌드입니다 — macOS Sequoia에선 '우클릭→열기'가 막혀, 첫 실행이 차단되면:
\`xattr -dr com.apple.quarantine /Applications/Pomopet.app\`
또는 시스템 설정 → 개인정보 보호 및 보안 → '그래도 열기'. (Homebrew 설치 시 불필요)"
GH_NOTES="$(printf '## 변경사항\n\n%s\n\n---\n\n%s\n' "$NOTES_MD" "$INSTALL_NOTE")"

# Sparkle appcast <description>용 HTML 변환 (### → 소제목, - → 목록 항목)
NOTES_HTML="$(printf '%s\n' "$NOTES_MD" | awk '
  BEGIN { inlist=0 }
  /^### / { if (inlist) { print "</ul>"; inlist=0 } h=$0; sub(/^### /,"",h); print "<h4>" h "</h4>"; next }
  /^- /   { if (!inlist) { print "<ul>"; inlist=1 } li=$0; sub(/^- /,"",li); print "<li>" li "</li>"; next }
  /^[[:space:]]*$/ { next }
  { print "<p>" $0 "</p>" }
  END { if (inlist) print "</ul>" }
')"

# 1) DMG 빌드 + sha256 추출
SHA="$(bash "$ROOT/scripts/package-dmg.sh" "$VERSION" | awk -F= '/^SHA256=/{print $2}')"
if [[ -z "$SHA" || ! -f "$DMG_PATH" ]]; then
  echo "DMG 생성 실패" >&2
  exit 1
fi
echo "sha256=$SHA"

# 2) GitHub Release 생성 (없으면) + DMG 업로드. 본문은 CHANGELOG 기반 변경사항 + 설치 안내.
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "▶︎ 기존 릴리스 $TAG 에 자산 덮어쓰기 + 노트 갱신…"
  gh release upload "$TAG" "$DMG_PATH" --repo "$REPO" --clobber
  gh release edit "$TAG" --repo "$REPO" --title "$APP_NAME $VERSION" --notes "$GH_NOTES"
else
  echo "▶︎ 릴리스 $TAG 생성…"
  gh release create "$TAG" "$DMG_PATH" \
    --repo "$REPO" \
    --target "$RELEASE_BRANCH" \
    --title "$APP_NAME $VERSION" \
    --notes "$GH_NOTES"
fi

# 2.5) Sparkle appcast 생성 → EdDSA 서명 → 릴리스 자산으로 업로드.
#   SUFeedURL = releases/latest/download/appcast.xml (Info.plist). sign_update가 Keychain의 개인키로 서명.
SIGN_TOOL="$(find "$ROOT/build/DerivedData" -path '*Sparkle*/bin/sign_update' ! -path '*old_dsa*' 2>/dev/null | head -1)"
if [[ -z "$SIGN_TOOL" ]]; then
  echo "⚠︎ sign_update 도구를 못 찾음(Sparkle 패키지 미resolve?). appcast 생략." >&2
else
  echo "▶︎ DMG EdDSA 서명 + appcast 생성…"
  SIG_ATTRS="$("$SIGN_TOOL" "$DMG_PATH")"   # → sparkle:edSignature="…" length="…"  (최초 1회 Keychain 접근 허용 필요)
  DMG_URL="https://github.com/${REPO}/releases/download/${TAG}/${APP_NAME}-${VERSION}.dmg"
  PUBDATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
  APPCAST="$ROOT/dist/appcast.xml"
  cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Pomopet</title>
    <item>
      <title>${VERSION}</title>
      <description><![CDATA[
${NOTES_HTML}
      ]]></description>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="${DMG_URL}" type="application/octet-stream" ${SIG_ATTRS} />
    </item>
  </channel>
</rss>
XML
  gh release upload "$TAG" "$APPCAST" --repo "$REPO" --clobber
  echo "✅ appcast 게시: https://github.com/${REPO}/releases/latest/download/appcast.xml"
fi

# 3) Homebrew cask 갱신 (탭 repo가 있을 때만)
TAP_DIR="$(mktemp -d)"
if gh repo clone "$TAP_REPO" "$TAP_DIR" -- -q 2>/dev/null; then
  CASK="$TAP_DIR/Casks/pomopet.rb"
  mkdir -p "$TAP_DIR/Casks"
  cat > "$CASK" <<EOF
cask "pomopet" do
  version "${VERSION}"
  sha256 "${SHA}"

  url "https://github.com/kes02/Pomopet/releases/download/v#{version}/Pomopet-#{version}.dmg"
  name "Pomopet"
  desc "Menu bar Pomodoro timer with an uploaded character that wakes up as you study"
  homepage "https://github.com/kes02/Pomopet"

  app "Pomopet.app"

  # 미서명 빌드: Gatekeeper 격리 속성 제거해 바로 실행되게 함
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Pomopet.app"]
  end

  zap trash: [
    "~/Library/Containers/com.kes02.Pomopet",
    "~/Library/Preferences/com.kes02.Pomopet.plist",
  ]
end
EOF
  ( cd "$TAP_DIR"
    git add Casks/pomopet.rb
    git commit -q -m "pomopet ${VERSION}" || true
    git push -q )
  echo "✅ Homebrew cask 갱신: $TAP_REPO (pomopet ${VERSION})"
else
  echo "ℹ︎ 탭 repo($TAP_REPO)가 없어 cask 갱신을 건너뜀. 먼저 탭을 만들어 주세요."
fi

rm -rf "$TAP_DIR"
echo "🎉 릴리스 완료: $TAG"
