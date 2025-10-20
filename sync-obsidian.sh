#!/bin/bash

# Obsidian → Hugo 변환 스크립트 (published: true만)

echo "🔄 Obsidian 파일 동기화 시작..."
echo ""

# content/posts 폴더 초기화
rm -rf content/posts
mkdir -p content/posts

# vault 전체에서 published: true인 .md 파일 찾기
# (.obsidian, .trash 등 시스템 폴더 제외)
find obsidian-vault -name "*.md" \
  -not -path "*/\.obsidian/*" \
  -not -path "*/\.trash/*" \
  -not -path "*/\.smtcmp*/*" \
  -not -path "*/\.tmp*/*" \
  -not -path "*/\.space/*" \
  -not -path "*/\.assets/*" \
  | while read file; do
  # frontmatter에서 published: true 확인
  if grep -q "^published: true" "$file"; then
    echo "✅ Publishing: $file"

    # 파일명 추출
    filename=$(basename "$file")

    # Wiki links 변환: [[title]] -> [title](/posts/title)
    sed 's/\[\[\([^]]*\)\]\]/[\1](\/posts\/\1)/g' "$file" > "content/posts/$filename"
  fi
done

echo ""
echo "✨ 동기화 완료!"
echo ""
echo "📝 발행된 글:"
ls -1 content/posts/ 2>/dev/null || echo "(없음)"
echo ""
