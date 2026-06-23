# 🐾 Pomopet

> 내가 올린 캐릭터가 매일 공부할 때마다 깨어나는 macOS 메뉴바 포모도로 타이머

Pomopet은 좋아하는 캐릭터 이미지를 **도트(픽셀)로 변환**해 키우는 메뉴바 앱입니다.
포모도로로 집중할 때마다 캐릭터가 깨어나고, 연속 기록(스트릭)이 쌓입니다.
하루를 거르면 캐릭터가 잿빛으로 잠들기 때문에 — **"내 캐릭터를 재우지 말자"**가 공부 동기가 됩니다. (듀오링고식 리텐션)

---

## ✨ 특징

- **🖼️ 내 캐릭터 업로드** — 좋아하는 이미지를 올리면 도트로 변환해 펫으로 사용
- **🔥 연속 기록(스트릭)** — 매일 목표를 채우면 연속일이 쌓이고, 끊기면 리셋
- **😴 활성/잠듦** — 오늘 목표 달성 시 캐릭터가 컬러로 깨어나 통통 튐 / 안 하면 흑백으로 잠듦
- **🏅 마일스톤 아우라** — 연속 3일 BRONZE → 7일 SILVER → 30일 GOLD → 100일 DIAMOND 테두리
- **🌱 활동 잔디(히트맵)** — 최근 35일 공부 기록을 한눈에
- **🎯 하루 목표** — 하루에 몇 세션을 채워야 "활성화"되는지 설정 (1~20)
- **🍅 단순한 포모도로** — 집중 / 휴식 / 하루 목표 세 가지만 설정하면 끝
- **🪶 가벼움** — Dock 아이콘 없이 메뉴바에만 존재. 모든 그래픽은 외부 이미지 없이 코드로 렌더링

---

## 📥 설치 & 실행

> 아직 정식 배포(서명·공증된 `.app`) 전이라, 소스에서 직접 빌드해 사용합니다.

### 요구 사항
- macOS 26.5 이상 (Xcode 프로젝트의 Deployment Target — 필요 시 낮출 수 있음)
- Xcode 16 이상

### 방법 1. Xcode에서 실행
```bash
git clone https://github.com/kes02/Pomopet.git
cd Pomopet
open Pomopet.xcodeproj
```
Xcode에서 `⌘R` (Run) → 메뉴바에 발바닥/달 아이콘이 나타납니다.

### 방법 2. 앱으로 빌드해서 설치
```bash
git clone https://github.com/kes02/Pomopet.git
cd Pomopet
xcodebuild -project Pomopet.xcodeproj -scheme Pomopet -configuration Release -derivedDataPath build
cp -R build/Build/Products/Release/Pomopet.app /Applications/
open /Applications/Pomopet.app
```
> 서명되지 않은 빌드라 처음 실행 시 우클릭 → "열기"로 Gatekeeper를 통과시켜야 할 수 있습니다.

---

## 🚀 사용법

1. 메뉴바 아이콘 클릭 → **키울 캐릭터 이미지 선택**
   - 투명 배경 PNG(누끼)를 넣으면 캐릭터만 또렷하게 떠서 가장 예쁩니다.
2. **집중 시작** → 타이머가 끝나면 한 세션 완료
3. 오늘 **하루 목표**만큼 세션을 채우면 캐릭터가 **활성화**(컬러로 깨어남) 🔥
4. 매일 이어가면 연속 기록과 잔디가 쌓입니다

### 화면 안내
| 버튼 | 기능 |
|---|---|
| 🐾 | 캐릭터 화면(홈)으로 |
| 📊 | 통계 · 연속 기록 · 활동 잔디 |
| ⚙️ | 설정 (집중/휴식/하루 목표, 캐릭터 바꾸기) |

### 설정
- **집중** — 한 세션 길이 (5~60분)
- **휴식** — 세션 후 쉬는 시간 (1~30분)
- **하루 목표** — 활성화에 필요한 하루 세션 수 (1~20)
- **캐릭터 바꾸기** — 이미지를 교체해도 연속 기록은 그대로 유지

> 하루 목표를 도중에 바꿔도, 이미 오늘 달성했다면 캐릭터는 잠들지 않고 연속 기록도 유지됩니다.

---

## 🛠️ 기술 스택

- **SwiftUI** · `MenuBarExtra` (메뉴바 전용 앱)
- **SwiftData** — 일일 기록·통계 영구 저장
- **Canvas** — 외부 이미지 없이 도트 렌더링 (`ImagePixelizer`가 업로드 이미지를 색 격자로 변환)

### 프로젝트 구조
```
Pomopet/Sources/
├─ App/        앱 진입점 (PomopetApp, 메뉴바 라벨)
├─ Core/       타이머·스트릭 로직 (PomopetController), 설정 (TimerSettings)
├─ Models/     SwiftData 모델 (DailyRecord, AppStats)
├─ Creatures/  도트 렌더링 (CustomPet, CharacterView)
└─ Views/      화면 (PopoverView, Stats/Settings)
```

---

## ⚠️ 캐릭터 이미지에 대하여

업로드 기능은 **사용자가 직접 고른 로컬 이미지**를 변환하는 개인용 기능입니다.
타인의 저작물(캐릭터 등)을 넣어 쓰는 경우, 개인 사용 범위를 지켜 주세요. 이 앱은 어떤 캐릭터 이미지도 포함·배포하지 않습니다.

---

## 📄 라이선스

개인용 프로젝트입니다.
