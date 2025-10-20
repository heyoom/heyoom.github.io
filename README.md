# 모요런 (MoyoRun) 블로그

> 코드와 러닝 사이, 40대 기획&개발자의 생각 저장소

## 기술 스택

- **CMS**: Obsidian
- **SSG**: Hugo (Coderon 테마)
- **호스팅**: GitHub Pages
- **도메인**: moyorun.com

## 워크플로우

1. **Obsidian에서 글 작성**
   - 기존 vault의 어디서든 작성 가능
   - frontmatter에 `published: true` 추가

2. **로컬 미리보기**
   ```bash
   ./sync-obsidian.sh
   # tmux에서 hugo server 실행 중 (http://localhost:1313)
   ```

3. **배포**
   ```bash
   git add .
   git commit -m "Add new post"
   git push
   # GitHub Actions 자동 실행 → 배포
   ```

## 폴더 구조

```
moyorun/
├── obsidian-vault/        # → Danny_iCloud (심볼릭 링크)
├── content/posts/         # 자동 생성 (published: true만)
├── themes/coderon/        # Hugo 테마
├── .github/workflows/     # 자동 배포
└── sync-obsidian.sh       # 로컬 동기화 스크립트
```

## 발행 예시

```markdown
---
title: "10km 완주"
date: 2025-10-20
published: true    ← 이것만 추가하면 발행
tags: [러닝]
---

# 내용...
```

## 로컬 개발

```bash
# Hugo 서버 시작 (tmux)
tmux new-session -d -s hugo_server
tmux send-keys -t hugo_server "hugo server -D" C-m

# Obsidian 파일 동기화
./sync-obsidian.sh
```

---

**블로그 주소**: https://moyorun.com (https://heyoom.github.io)
