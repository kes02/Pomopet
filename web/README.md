# web/ — Pomopet 랜딩 페이지

빌드 없는 정적 페이지 한 장입니다. `index.html` 하나에 CSS·JS가 다 들어 있고, 이미지만 `img/`에 있습니다.

## 로컬에서 보기

```bash
cd web && python3 -m http.server 8000   # → http://localhost:8000
```

`file://`로 열어도 대부분 동작하지만, 이미지 업로드 데모의 `getImageData`가 브라우저에 따라 막히므로 위 방법을 권합니다.

## 배포 (Vercel)

같은 레포에서 배포합니다. Vercel 프로젝트를 만들 때:

- **Root Directory**: `web`
- **Framework Preset**: Other
- **Build Command**: 비움
- **Output Directory**: 비움 (`.` 로 두면 됩니다)

`main`에 푸시하면 프로덕션이 갱신되고, 다른 브랜치는 프리뷰 URL이 붙습니다.

## 스크린샷 갱신

`docs/screenshots/`가 원본입니다. 앱 UI가 바뀌면 원본을 먼저 갱신하고 복사하세요.

```bash
cp docs/screenshots/ko/*.png web/img/ko/
cp docs/screenshots/en/*.png web/img/en/
cp docs/screenshots/bar/*.png web/img/bar/
```

## 히어로 데모에 대해

방문자가 올린 이미지를 26×26 격자로 변환해 보여줍니다. 앱의 `ImagePixelizer`와 같은 값을 씁니다.

- 격자 크기 `26` — `CustomPet.renderResolution`
- 투명 판정 알파 `0.25` — `ImagePixelizer.colorGrid`
- 칸 색 = 그 칸에 걸친 원본 픽셀의 평균색

앱 쪽 값을 바꾸면 `index.html`의 `N`, `ALPHA_MIN`도 같이 맞춰야 데모가 실제와 어긋나지 않습니다.
변환은 전부 브라우저 안에서 일어나고 아무 데도 전송하지 않습니다. 기본 펫은 코드로 그린 도트라 외부 캐릭터 이미지를 포함하지 않습니다.
