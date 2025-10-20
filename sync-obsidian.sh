#!/bin/bash

# Obsidian → Hugo 변환 스크립트 (published: true만)

echo "🔄 Obsidian 파일 동기화 시작..."
echo ""

# content/posts, static/images 폴더 초기화
rm -rf content/posts
mkdir -p content/posts static/images

# vault 전체에서 published: true인 .md 파일 찾기
# (.obsidian, .trash 등 시스템 폴더 제외)
find -L obsidian-vault -name "*.md" \
  -not -path "*/\.obsidian/*" \
  -not -path "*/\.trash/*" \
  -not -path "*/\.smtcmp*/*" \
  -not -path "*/\.tmp*/*" \
  -not -path "*/\.space/*" \
  -not -path "*/\.assets/*" \
  2>/dev/null \
  | while read file; do
  # frontmatter에서 published: true 또는 published: "true" 확인
  if grep -qE "^published: (true|\"true\")" "$file"; then
    echo "✅ Publishing: $file"

    # 파일명 추출
    filename=$(basename "$file")
    title=$(basename "$file" .md)

    # Wiki links 변환, published 필드 제거, title 추가
    temp_file="/tmp/hugo_convert_$$.md"
    {
      # frontmatter 시작
      echo "---"
      # title이 없으면 추가
      if ! grep -q "^title:" "$file"; then
        echo "title: \"$title\""
      fi
      # 기존 frontmatter 복사 (published 제외)
      sed -n '/^---$/,/^---$/p' "$file" | sed '1d;$d' | grep -v "^published:"
      echo "---"
      # 본문 복사 (frontmatter 이후)
      awk '/^---$/ {count++; next} count >= 2 {print}' "$file"
    } > "$temp_file"

    # Python으로 Wiki links 변환 (URL 인코딩 포함)
    python3 -c "
import re
import urllib.parse
import sys

with open('$temp_file', 'r', encoding='utf-8') as f:
    content = f.read()

# 이미지 링크 변환: ![[image.png]] -> ![image.png](/images/image.png)
def encode_image(match):
    img = match.group(1)
    encoded = urllib.parse.quote(img)
    return f'![{img}](/images/{encoded})'

# 내부 링크 변환: [[title]] -> [title](/posts/title.md)
def encode_link(match):
    title = match.group(1)
    # 파일명으로 변환 (Hugo slug 방식)
    slug = title.lower().replace(' ', '-')
    return f'[{title}](/posts/{slug})'

content = re.sub(r'!\[\[([^\]]+)\]\]', encode_image, content)
content = re.sub(r'\[\[([^\]]+)\]\]', encode_link, content)

print(content, end='')
" > "content/posts/$filename"

    rm -f "$temp_file"

    # 이미지 파일 복사
    file_dir=$(dirname "$file")
    if [ -d "$file_dir/assets" ]; then
      find "$file_dir/assets" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.webp" \) -exec cp {} static/images/ \; 2>/dev/null
    fi
  fi
done

echo ""
echo "✨ 동기화 완료!"
echo ""
echo "📝 발행된 글:"
ls -1 content/posts/ 2>/dev/null || echo "(없음)"
echo ""
