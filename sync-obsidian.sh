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

    # Wiki links 변환, published 필드 제거, title/date 추가
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
      # date 필드가 없으면 파일명에서 추출해서 추가
      if ! grep -q "^date:" "$file"; then
        # 파일명이 YYYY-MM-DD 형식인 경우 날짜 추출
        if [[ "$title" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
          echo "date: $title"
        fi
      fi
      echo "---"
      # 본문 복사 (frontmatter 이후)
      awk '/^---$/ {count++; next} count >= 2 {print}' "$file"
    } > "$temp_file"

    # Python으로 Wiki links 변환 및 image 필드 추가
    python3 -c "
import re
import urllib.parse
import sys

with open('$temp_file', 'r', encoding='utf-8') as f:
    content = f.read()

# frontmatter와 본문 분리
match = re.match(r'(---\n)(.*?)(---\n)(.*)', content, re.DOTALL)
if not match:
    print(content, end='')
    sys.exit()

frontmatter_start = match.group(1)
frontmatter = match.group(2)
frontmatter_end = match.group(3)
body = match.group(4)

# 본문에서 첫 번째 이미지 찾기
first_image = None
image_match = re.search(r'!\[\[([^\]]+)\]\]', body)
if image_match:
    first_image = image_match.group(1)
    first_image_encoded = urllib.parse.quote(first_image)

# 본문에서 description 추출 (일반 텍스트만, 160자 제한)
description = None
text_lines = []
for line in body.split('\n'):
    line = line.strip()
    # 빈 줄, 헤더, 이미지, 리스트 건너뛰기 (코드 블록 체크 제거)
    if line and not line.startswith('#') and not line.startswith('!') and not line.startswith('-') and not line.startswith('*') and not line.startswith('>'):
        # Markdown 문법 제거: **, __, [[]], []()
        clean_line = re.sub(r'\*\*([^*]+)\*\*', r'\1', line)  # **bold**
        clean_line = re.sub(r'__([^_]+)__', r'\1', clean_line)  # __bold__
        clean_line = re.sub(r'\*([^*]+)\*', r'\1', clean_line)  # *italic*
        clean_line = re.sub(r'_([^_]+)_', r'\1', clean_line)  # _italic_
        clean_line = re.sub(r'\[\[([^\]]+)\]\]', r'\1', clean_line)  # [[link]]
        clean_line = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', clean_line)  # [text](url)
        # HTML 태그 제거
        clean_line = re.sub(r'<[^>]+>', '', clean_line)
        clean_line = clean_line.strip()
        if clean_line:
            text_lines.append(clean_line)
            # 160자까지 채우기
            if len(' '.join(text_lines)) >= 160:
                break

if text_lines:
    description = ' '.join(text_lines)[:160]

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

body = re.sub(r'!\[\[([^\]]+)\]\]', encode_image, body)
body = re.sub(r'\[\[([^\]]+)\]\]', encode_link, body)

# frontmatter에 image 필드 추가 (첫 번째 이미지가 있고, image 필드가 없으면)
if first_image and 'image:' not in frontmatter:
    frontmatter = frontmatter.rstrip() + f'\nimage: /images/{first_image_encoded}\n'

# frontmatter에 description 필드 추가 (description 필드가 없으면)
if description and 'description:' not in frontmatter:
    # 따옴표 이스케이프 처리
    description_escaped = description.replace('\"', '\\\"')
    frontmatter = frontmatter.rstrip() + f'\ndescription: \"{description_escaped}\"\n'

# 재조합
result = frontmatter_start + frontmatter + frontmatter_end + body
print(result, end='')
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
