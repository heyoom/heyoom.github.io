# MoyoRun 블로그 프로젝트 가이드

> Obsidian + Hugo + GitHub Pages 기반 개인 블로그
> **도메인**: https://moyorun.com (https://heyoom.github.io)

## 프로젝트 개요

옵시디언 vault에서 작성한 마크다운 파일을 Hugo 정적 사이트로 자동 변환하여 GitHub Pages에 배포하는 블로그 시스템입니다.

### 핵심 원칙

1. **Single Source of Truth**: 옵시디언 vault가 원본
2. **선택적 발행**: `publish: true` 플래그로 제어
3. **자동화**: 변환/배포 과정 전부 자동화
4. **Hugo 네이티브**: 최종 결과물은 표준 Hugo 사이트

## 기술 스택

- **CMS**: Obsidian (원본 작성)
- **SSG**: Hugo 0.140.0+ (Coderon 테마)
- **호스팅**: GitHub Pages
- **도메인**: moyorun.com
- **배포**: GitHub Actions (자동)
- **언어**: Bash, Python 3

## 폴더 구조

```
moyorun/
├── obsidian-vault/              # → Danny_iCloud (심볼릭 링크)
│   └── *.md                     # publish: true인 파일만 발행
├── content/
│   ├── *.md                     # [자동 생성] 독립 페이지 (type: page)
│   └── posts/                   # [자동 생성] 블로그 포스트
├── static/images/               # [자동 생성] 이미지 파일
├── themes/coderon/              # Hugo 테마 (submodule)
├── .github/workflows/           # 자동 배포 설정
│   └── deploy.yml
├── sync-obsidian.sh             # 핵심 변환 스크립트
├── hugo.toml                    # Hugo 설정
└── CLAUDE.md                    # 이 파일
```

## 워크플로우

### 빠른 시작

```bash
# 옵시디언에서 글 작성 (publish: true 추가)
# ↓
./sync-obsidian.sh --push
# ↓
# 완료! (sync + commit + push + 배포)
```

### 1. 글 작성 (Obsidian)

옵시디언 vault의 **어디서든** 작성 가능.

```markdown
---
title: "10km 완주"
created: 2025.10.20
tags: [러닝, 완주]
categories: [러닝]
publish: true    ← 이것만 추가하면 발행
---

# 내용...
![[이미지.png]]       ← 자동으로 Hugo 형식으로 변환
[[다른글]]            ← 내부 링크도 자동 변환
```

**Frontmatter 규칙**:
- `publish: true`: **필수** (발행 여부)
- `type: page`: 독립 페이지로 발행 (생략시 블로그 포스트)
- `title`: 없으면 파일명으로 자동 생성
- `date`: 없으면 `created` 또는 파일명(YYYY-MM-DD)에서 추출
- `tags`, `categories`: 선택 (Hugo taxonomy)
- `image`: 없으면 본문 첫 번째 이미지로 자동 설정
- `description`: 없으면 본문 첫 160자로 자동 생성

**발행 타입**:
- `publish: true` (기본) → `content/posts/` (블로그 포스트, 목록 표시)
- `publish: true` + `type: page` → `content/` (독립 페이지, 메뉴/링크로만 접근)

**페이지 타입 예시**:
```markdown
# 블로그 포스트 (기본)
---
title: "10km 완주"
publish: true
tags: [러닝]
---

# 독립 페이지 (about, 소개 등)
---
title: "소개"
type: page
publish: true
---
```

### 2. 로컬 미리보기

```bash
# 1. Obsidian → Hugo 변환
./sync-obsidian.sh                # 증분 sync (변경된 파일만, 빠름)
./sync-obsidian.sh --full         # 전체 재생성 (모든 파일, 느림)
./sync-obsidian.sh --push         # 증분 sync + git push
./sync-obsidian.sh --full --push  # 전체 sync + git push

# 2. Hugo 서버 실행 (tmux에서 한 번만)
tmux new-session -d -s hugo_server
tmux send-keys -t hugo_server "hugo server -D" C-m

# 3. 브라우저에서 확인
# http://localhost:1313
```

**sync-obsidian.sh 옵션**:
- **기본 (증분 sync)**: 변경된 파일만 변환 (mtime 기반)
  - 빠름 (수백 개 파일 중 변경된 것만)
  - `publish: false`로 변경된 파일은 자동 삭제
  - 일상적인 작업에 사용
- **--full (전체 sync)**: 모든 파일 재생성
  - content/ 폴더 초기화 후 전체 변환
  - 스크립트 수정 후 또는 문제 발생시 사용
- **--push**: sync 후 자동 git push
  - 변경사항 감지 → git add, commit, push
  - 커밋 메시지 자동 생성 (변경 파일 개수 포함)
  - 변경사항 없으면 push 건너뜀
  - GitHub Actions 자동 배포

**Hugo 서버 관리**:
```bash
# 로그 확인
tmux capture-pane -t hugo_server -p -S -100

# 재시작 (필요시)
tmux kill-session -t hugo_server
tmux new-session -d -s hugo_server
tmux send-keys -t hugo_server "hugo server -D" C-m
```

### 3. 배포

**권장 방법 (자동)**:
```bash
./sync-obsidian.sh --push
```

**수동 방법**:
```bash
git add .
git commit -m "Add new post: 제목"
git push
```

→ GitHub Actions 자동 실행 (1~2분 소요)
→ https://moyorun.com 배포 완료

**커밋 메시지 예시** (`--push` 사용시 자동 생성):
```
Sync blog: 3 post(s), 1 page(s), 2 image(s)

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>
```

## sync-obsidian.sh 동작 방식

### 증분 sync (기본)

1. **기존 파일 목록 수집**: `content/posts/`, `content/*.md`
2. **vault 스캔**: `publish: true` 파일 찾기
3. **각 파일 처리**:
   - **출력 경로 결정**: `type: page` 여부 확인
   - **mtime 비교**: 원본 > 출력 또는 출력 파일 없으면 변환
   - **Skip**: 변경되지 않은 파일 (로그만 출력)
   - **처리된 파일 목록에서 제거**
4. **삭제 처리**: 목록에 남은 파일 삭제 (publish: false로 변경됨)
5. **이미지 복사**: 누락된 이미지 추가

**장점**: 빠름 (변경된 파일만), 일상 사용에 적합

### 전체 sync (--full)

1. **폴더 초기화**: `content/posts/` 삭제, `content/*.md` 삭제
2. **vault 스캔**: `publish: true` 파일 찾기
3. **모든 파일 변환**: 변경 여부 무관하게 전부 재생성
4. **이미지 복사**: 모든 이미지 재처리

**사용 시점**: 스크립트 수정 후, 문제 발생시

### 파일 변환 로직 (공통)

1. **출력 경로 결정**:
   - `type: page` 있으면 → `content/파일명.md` (독립 페이지)
   - `type: page` 없으면 → `content/posts/파일명.md` (블로그 포스트)
2. **Frontmatter 처리**:
   - `publish` 필드 제거
   - `title` 없으면 파일명으로 추가
   - `date` 없으면 `created` 또는 파일명에서 추출
   - `image` 없으면 본문 첫 이미지로 설정
   - `description` 없으면 본문 텍스트 추출 (160자)
3. **본문 변환**:
   - `![[이미지.png]]` → `![이미지.png](/images/이미지.png)`
   - `[[링크]]` → `[링크](/posts/링크)`
   - URL encoding 처리 (공백 등)
4. **이미지 복사**: vault의 assets → `static/images/`
5. **출력**: 결정된 경로로 저장

### 주의사항

⚠️ **sync-obsidian.sh 수정시 반드시 테스트**:
```bash
# 변경 전 백업
cp sync-obsidian.sh sync-obsidian.sh.backup

# 증분 sync 테스트
./sync-obsidian.sh

# 전체 sync 테스트
./sync-obsidian.sh --full

# Hugo 서버로 확인
hugo server -D

# 확인 후 커밋
git add sync-obsidian.sh
git commit -m "Update sync script: 변경 내용"
```

⚠️ **절대 수동으로 content/ 수정 금지**:
- `content/posts/`, `content/*.md`는 sync 스크립트가 관리
- **증분 sync**: 변경된 파일만 덮어씀 (수동 수정하면 다음 sync때 날아감)
- **전체 sync**: 전부 삭제 후 재생성
- 수정사항은 반드시 옵시디언 원본에서

⚠️ **이미지 파일명 규칙**:
- 특수문자 피하기 (공백, 한글 가능하지만 영문 권장)
- URL encoding 자동 처리됨

## Git 커밋 규칙

### 커밋 메시지 형식

```
<type>: <subject>

[optional body]

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>
```

### Type 종류

- `Add`: 새 글 추가
- `Update`: 기존 글 수정
- `Fix`: 버그 수정
- `Feat`: 기능 추가 (블로그 시스템)
- `Style`: CSS/레이아웃 변경
- `Refactor`: 스크립트/코드 리팩토링
- `Chore`: 설정 파일 변경

### 예시

```bash
# 새 글
git commit -m "Add: 10km 완주 후기"

# 글 수정
git commit -m "Update: 10km 완주 후기 오타 수정"

# 시스템 수정
git commit -m "Fix: sync-obsidian.sh 이미지 경로 처리 버그 수정"

# 기능 추가
git commit -m "Feat: 카테고리별 태그 색상 구분 추가"
```

## Hugo 테마 커스터마이징

### 파일 위치

- **테마 원본**: `themes/coderon/` (submodule, 직접 수정 금지)
- **커스텀 오버라이드**: 프로젝트 루트에 생성
  - `layouts/` → 테마 레이아웃 오버라이드
  - `static/css/custom.css` → 추가 스타일
  - `hugo.toml` → 테마 설정

### 현재 커스터마이징

1. **카테고리 표시** (`layouts/_default/single.html`)
2. **컬러풀 태그** (`layouts/_default/index.json`, `layouts/partials/sidebar-widgets/widget-tags.html`)
3. **Featured posts** (`hugo.toml`: `mainSections`)
4. **커스텀 스타일** (`static/css/custom.css`)

## 배포 확인

### GitHub Actions 로그 확인

```bash
# 최근 워크플로우 확인
gh run list --limit 5

# 특정 run 로그 확인
gh run view <run-id>

# 실패시 재실행
gh run rerun <run-id>
```

### 사이트 확인

```bash
# 메인 도메인
curl -I https://moyorun.com/

# GitHub Pages (fallback)
curl -I https://heyoom.github.io/
```

## 트러블슈팅

### Hugo 빌드 실패

1. **로컬 빌드 테스트**:
   ```bash
   hugo --minify
   ```

2. **YAML 파싱 에러**:
   - frontmatter에 특수문자 확인 (따옴표 이스케이프)
   - 제어 문자 확인 (`cat -v content/posts/문제파일.md`)

3. **이미지 누락**:
   - `static/images/` 확인
   - vault에서 이미지 파일 존재 확인

### sync-obsidian.sh 문제

1. **변환 안 됨**:
   - `publish: true` 정확히 입력 확인
   - frontmatter 형식 확인 (`---`로 시작/끝)

2. **이미지 깨짐**:
   - 파일명 특수문자 확인
   - vault 경로 확인

3. **날짜 추출 실패**:
   - `created` 필드 형식: `YYYY.MM.DD` 또는 `YYYY-MM-DD`
   - 파일명 형식: `YYYY-MM-DD.md`

## 개발시 주의사항

1. **절대 수동 편집 금지**: `content/posts/`, `static/images/`
2. **테마 submodule 직접 수정 금지**: 오버라이드 사용
3. **tmux 사용**: `hugo server` 직접 bash 실행 금지
4. **충분한 테스트**: sync 스크립트 수정시 반드시 로컬 테스트
5. **에러 0개 원칙**: `hugo --minify` 에러 없이 통과 확인

## 유용한 명령어

```bash
# 발행된 글 개수
ls -1 content/posts/ | wc -l

# 최근 변경 파일 (vault)
find -L obsidian-vault -name "*.md" -mtime -7 -exec grep -l "publish: true" {} \;

# 이미지 사용 확인
grep -r "!\[" content/posts/ | wc -l

# Hugo 버전 확인
hugo version

# 테마 업데이트
git submodule update --remote themes/coderon
```

## 참고 링크

- **Hugo 문서**: https://gohugo.io/documentation/
- **Coderon 테마**: https://github.com/jekuer/hugo-theme-coderon
- **GitHub Actions**: https://github.com/heyoom/heyoom.github.io/actions
- **블로그**: https://moyorun.com
