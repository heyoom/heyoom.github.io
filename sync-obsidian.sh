#!/bin/bash

# Obsidian → Hugo 변환 스크립트 (publish: true만)
# 사용법:
#   ./sync-obsidian.sh                      # 증분 sync (변경된 파일만)
#   ./sync-obsidian.sh --full               # 전체 재생성
#   ./sync-obsidian.sh --clean-images       # 증분 sync + unused 이미지 정리
#   ./sync-obsidian.sh --full --clean-images # 전체 sync + unused 이미지 정리
#   ./sync-obsidian.sh --push               # sync + git push
#   ./sync-obsidian.sh --full --push        # 전체 sync + git push
#   ./sync-obsidian.sh --clean-images --push # sync + 이미지 정리 + git push

# 옵션 파싱
FULL_SYNC=false
PUSH_TO_GIT=false
CLEAN_IMAGES=false

for arg in "$@"; do
  case $arg in
    --full)
      FULL_SYNC=true
      ;;
    --push)
      PUSH_TO_GIT=true
      ;;
    --clean-images)
      CLEAN_IMAGES=true
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: $0 [--full] [--push] [--clean-images]"
      exit 1
      ;;
  esac
done

# 파일 변환 함수
convert_file() {
  local source_file="$1"
  local output_path="$2"

  filename=$(basename "$source_file")
  title=$(basename "$source_file" .md)

  # Wiki links 변환, publish 필드 제거, title/date 추가
  temp_file="/tmp/hugo_convert_$$.md"
  {
    # frontmatter 시작
    echo "---"

    # title 처리: 없거나 빈 값이면 파일명으로 추가
    title_value=$(grep "^title:" "$source_file" | sed 's/^title: *//' | tr -d '"' | tr -d "'" | xargs)
    if [ -z "$title_value" ]; then
      echo "title: \"$title\""
    else
      echo "title: $title_value"
    fi

    # 기존 frontmatter 복사 (publish, published, title 제외)
    sed -n '/^---$/,/^---$/p' "$source_file" | sed '1d;$d' | grep -v "^publish:" | grep -v "^published:" | grep -v "^title:"
    # date 필드가 없으면 추출해서 추가
    if ! grep -q "^date:" "$source_file"; then
      # 1) 파일명이 YYYY-MM-DD 형식인 경우
      if [[ "$title" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "date: $title"
      # 2) created 필드에서 날짜 추출 (YYYY-MM-DD 또는 YYYY. MM. DD 형식)
      elif grep -q "^created:" "$source_file"; then
        created_date=$(grep "^created:" "$source_file" | sed 's/created: *//' | sed 's/[. ]\+/-/g' | cut -d' ' -f1 | cut -d'-' -f1-3)
        if [[ "$created_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
          echo "date: $created_date"
        fi
      fi
    fi
    echo "---"
    # 본문 복사 (frontmatter 이후)
    awk '/^---$/ {count++; next} count >= 2 {print}' "$source_file"
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
# Obsidian 형식 먼저 확인
image_match = re.search(r'!\[\[([^\]]+)\]\]', body)
if image_match:
    first_image = image_match.group(1).split('/')[-1]  # 파일명만 추출
else:
    # Markdown 표준 형식 확인
    image_match = re.search(r'!\[([^\]]*)\]\(([^)]+)\)', body)
    if image_match:
        img_path = image_match.group(2)
        # http로 시작하는 외부 이미지는 제외
        if not img_path.startswith('http'):
            first_image = img_path.split('/')[-1]  # 파일명만 추출

if first_image:
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

# 연속된 2개 이상의 이미지를 gallery로 변환
lines = body.split('\n')
result_lines = []
i = 0
while i < len(lines):
    line = lines[i].strip()

    # 현재 줄이 Obsidian 이미지 형식인지 확인
    if re.match(r'!\[\[([^\]]+)\]\]$', line):
        # 연속된 이미지 모으기 (빈 줄 없이 연속된 경우만)
        images = [line]
        next_i = i + 1

        while next_i < len(lines):
            if lines[next_i].strip() == '':
                break  # 빈 줄을 만나면 중단 (gallery 변환 안 함)
            if re.match(r'!\[\[([^\]]+)\]\]$', lines[next_i].strip()):
                images.append(lines[next_i].strip())
                next_i += 1
            else:
                break

        # 2개 이상이면 gallery로 변환
        if len(images) >= 2:
            result_lines.append('')
            result_lines.append('{{< gallery columns=\"2\" >}}')

            for img_line in images:
                img = re.match(r'!\[\[([^\]]+)\]\]', img_line).group(1).split('/')[-1]
                img_encoded = urllib.parse.quote(img)
                result_lines.append(f'  {{{{< img src=\"/images/{img_encoded}\" >}}}}')

            result_lines.append('{{< /gallery >}}')
            result_lines.append('')
            i = next_i
        else:
            # 단일 이미지 → 일반 변환
            img = re.match(r'!\[\[([^\]]+)\]\]', line).group(1).split('/')[-1]
            img_encoded = urllib.parse.quote(img)
            result_lines.append(f'![{img}](/images/{img_encoded})')
            i += 1
    else:
        result_lines.append(lines[i])
        i += 1

body = '\n'.join(result_lines)

# Markdown 표준 이미지 변환: ![alt](image.png) -> ![alt](/images/image.png)
def encode_markdown_image(match):
    alt_text = match.group(1)
    img_path = match.group(2)

    # 이미 /images/로 시작하거나 http로 시작하면 변환 안함
    if img_path.startswith('/images/') or img_path.startswith('http'):
        return match.group(0)

    # assets/ 경로나 상대경로에서 파일명만 추출
    img_basename = img_path.split('/')[-1]
    encoded = urllib.parse.quote(img_basename)
    return f'![{alt_text}](/images/{encoded})'

# 내부 링크 변환: [[title]] -> [title](/posts/title.md)
def encode_link(match):
    title = match.group(1)
    # 파일명으로 변환 (Hugo slug 방식)
    slug = title.lower().replace(' ', '-')
    return f'[{title}](/posts/{slug})'

# Markdown 표준 이미지 형식 변환
body = re.sub(r'!\[([^\]]*)\]\(([^)]+)\)', encode_markdown_image, body)
# 내부 링크 변환
body = re.sub(r'\[\[([^\]]+)\]\]', encode_link, body)

# frontmatter에 image 필드 추가 (첫 번째 이미지가 있고, image 필드가 없으면)
if first_image and 'image:' not in frontmatter:
    first_image_encoded = urllib.parse.quote(first_image)
    frontmatter = frontmatter.rstrip() + f'\nimage: /images/{first_image_encoded}\n'

# frontmatter에 description 필드 추가 (description 필드가 없으면)
if description and 'description:' not in frontmatter:
    # 따옴표 이스케이프 처리
    description_escaped = description.replace('\"', '\\\"')
    frontmatter = frontmatter.rstrip() + f'\ndescription: \"{description_escaped}\"\n'

# 재조합
result = frontmatter_start + frontmatter + frontmatter_end + body
print(result, end='')
" > "$output_path"

  rm -f "$temp_file"

  # 이 포스트에서 사용된 이미지 파일 복사
  {
    # Markdown 이미지: ![alt](/images/filename)
    grep -oh '!\[[^]]*\](/images/[^)]*' "$output_path" 2>/dev/null | sed 's|!\[[^]]*\](/images/||'
    # Hugo shortcode: {{< img src="/images/filename" >}}
    grep -oh 'src="/images/[^"]*"' "$output_path" 2>/dev/null | sed 's|src="/images/||; s|"$||'
  } | sort -u | while read encoded_img; do
    # Python으로 URL decode (한글, 특수문자 포함)
    img=$(python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]))" "$encoded_img")
    # static/images에 이미 있으면 건너뛰기
    if [ ! -f "static/images/$img" ]; then
      # vault의 assets 폴더에서 이미지 찾기
      found=$(find -L obsidian-vault -name "$img" 2>/dev/null | head -1)
      if [ -n "$found" ]; then
        cp "$found" "static/images/"
      fi
    fi
  done
}

# 전체 sync 함수 (기존 방식)
full_sync() {
  echo "🔄 전체 동기화 시작..."
  echo ""

  # 중복 파일명 체크
  check_duplicate_filenames

  # content/posts 폴더 초기화
  rm -rf content/posts
  mkdir -p content/posts

  # content/의 .md 파일 삭제 (type: page)
  find content -maxdepth 1 -name "*.md" -delete

  # static/images 폴더 생성
  mkdir -p static/images

  # vault 전체에서 publish: true인 .md 파일 찾기
  find -L obsidian-vault -name "*.md" \
    -not -path "*/\.obsidian/*" \
    -not -path "*/\.trash/*" \
    -not -path "*/\.smtcmp*/*" \
    -not -path "*/\.tmp*/*" \
    -not -path "*/\.space/*" \
    -not -path "*/\.assets/*" \
    2>/dev/null \
    | while read file; do
    # frontmatter에서 publish: true 확인
    if grep -qE "^publish: (true|\"true\")" "$file"; then
      filename=$(basename "$file")

      # type 필드 확인하여 출력 경로 결정
      if grep -qE "^type: page" "$file"; then
        output_path="content/$filename"
        echo "✅ Publishing (page): $file"
      else
        output_path="content/posts/$filename"
        echo "✅ Publishing (post): $file"
      fi

      convert_file "$file" "$output_path"
    fi
  done
}

# 중복 파일명 감지 함수
check_duplicate_filenames() {
  echo "🔍 중복 파일명 확인 중..."

  duplicates_found=false
  seen_files="/tmp/sync_seen_files_$$.txt"
  > "$seen_files"

  find -L obsidian-vault -name "*.md" \
    -not -path "*/\.obsidian/*" \
    -not -path "*/\.trash/*" \
    -not -path "*/\.smtcmp*/*" \
    -not -path "*/\.tmp*/*" \
    -not -path "*/\.space/*" \
    -not -path "*/\.assets/*" \
    2>/dev/null \
    | while read file; do
    if grep -qE "^publish: (true|\"true\")" "$file"; then
      filename=$(basename "$file")

      # 이미 본 파일명인지 확인
      if grep -qxF "$filename" "$seen_files"; then
        if [ "$duplicates_found" = false ]; then
          echo ""
          echo "⚠️  경고: publish: true인 중복 파일명 발견!"
          echo ""
        fi
        echo "  ❌ $filename"
        echo "     - $file"
        # 이전에 발견된 파일도 출력
        prev_file=$(find -L obsidian-vault -name "$filename" \
          -not -path "*/\.obsidian/*" \
          -not -path "*/\.trash/*" \
          2>/dev/null | grep -v "^${file}$" | head -1)
        if [ -n "$prev_file" ]; then
          echo "     - $prev_file"
        fi
        echo ""
        duplicates_found=true
      else
        echo "$filename" >> "$seen_files"
      fi
    fi
  done

  rm -f "$seen_files"

  if [ "$duplicates_found" = true ]; then
    echo "⚠️  중복 파일명은 나중에 처리된 것만 발행됩니다."
    echo "⚠️  파일명을 다르게 변경하거나 하나만 publish: true로 설정하세요."
    echo ""
    return 1
  else
    echo "  ✓ 중복 없음"
    echo ""
  fi

  return 0
}

# 증분 sync 함수
incremental_sync() {
  echo "🔄 증분 동기화 시작..."
  echo ""

  # 중복 파일명 체크
  check_duplicate_filenames

  # 폴더 생성
  mkdir -p content/posts static/images

  # 기존 파일 목록 수집 (임시 파일 사용)
  existing_files_list="/tmp/sync_existing_files_$$.txt"
  > "$existing_files_list"  # 파일 초기화

  # content/posts/의 .md 파일
  if [ -d content/posts ]; then
    find content/posts -maxdepth 1 -name "*.md" >> "$existing_files_list" 2>/dev/null
  fi

  # content/의 .md 파일 (type: page)
  find content -maxdepth 1 -name "*.md" >> "$existing_files_list" 2>/dev/null

  # vault에서 publish: true인 파일 처리
  while IFS= read -r source_file; do
    # frontmatter에서 publish: true 확인
    if grep -qE "^publish: (true|\"true\")" "$source_file"; then
      filename=$(basename "$source_file")

      # type 필드 확인하여 출력 경로 결정
      if grep -qE "^type: page" "$source_file"; then
        output_path="content/$filename"
        file_type="page"
      else
        output_path="content/posts/$filename"
        file_type="post"
      fi

      # mtime 비교 (파일이 없거나 변경되었으면 변환)
      needs_conversion=false
      if [ ! -f "$output_path" ]; then
        needs_conversion=true
        echo "➕ New ($file_type): $source_file"
      elif [ "$source_file" -nt "$output_path" ]; then
        needs_conversion=true
        echo "🔄 Updated ($file_type): $source_file"
      else
        echo "⏭️  Skip ($file_type): $source_file"
      fi

      if [ "$needs_conversion" = true ]; then
        convert_file "$source_file" "$output_path"
      fi

      # 처리된 파일은 목록에서 제거 (삭제 대상에서 제외)
      grep -v "^${output_path}$" "$existing_files_list" > "${existing_files_list}.tmp" 2>/dev/null || true
      mv "${existing_files_list}.tmp" "$existing_files_list"
    fi
  done < <(find -L obsidian-vault -name "*.md" \
    -not -path "*/\.obsidian/*" \
    -not -path "*/\.trash/*" \
    -not -path "*/\.smtcmp*/*" \
    -not -path "*/\.tmp*/*" \
    -not -path "*/\.space/*" \
    -not -path "*/\.assets/*" \
    2>/dev/null)

  # 처리되지 않은 파일 삭제 (vault에 없거나 published: false)
  while IFS= read -r old_file; do
    if [ -f "$old_file" ]; then
      echo "🗑️  Delete: $old_file"
      rm -f "$old_file"
    fi
  done < "$existing_files_list"

  # 임시 파일 삭제
  rm -f "$existing_files_list"
}

# Unused 이미지 정리 함수
cleanup_unused_images() {
  echo ""
  echo "🧹 Unused 이미지 정리 시작..."
  echo ""

  # content/에서 사용 중인 이미지 목록 추출
  used_images_list="/tmp/sync_used_images_$$.txt"
  > "$used_images_list"

  # content/posts/, content/*.md에서 이미지 참조 추출
  if [ -d content/posts ] || [ -n "$(ls -A content/*.md 2>/dev/null)" ]; then
    {
      # Markdown 이미지: ![alt](/images/filename)
      grep -roh '!\[[^]]*\](/images/[^)]*' content/ 2>/dev/null | sed 's|!\[[^]]*\](/images/||'
      # Hugo shortcode: {{< img src="/images/filename" >}}
      grep -roh 'src="/images/[^"]*"' content/ 2>/dev/null | sed 's|src="/images/||; s|"$||'
    } | python3 -c "
import sys
import urllib.parse
for line in sys.stdin:
    decoded = urllib.parse.unquote(line.strip())
    if decoded:
        print(decoded)
" | sort -u > "$used_images_list"
  fi

  # hugo.toml에서 참조되는 이미지 추가 (보호 대상)
  if [ -f hugo.toml ]; then
    grep -Eo '"/images/[^"]+' hugo.toml 2>/dev/null | \
      sed 's|"/images/||' | \
      python3 -c "
import sys
import urllib.parse
for line in sys.stdin:
    decoded = urllib.parse.unquote(line.strip())
    if decoded:
        print(decoded)
" >> "$used_images_list"
  fi

  # 중복 제거
  sort -u "$used_images_list" -o "$used_images_list"

  # static/images/의 모든 이미지 목록
  all_images_list="/tmp/sync_all_images_$$.txt"
  > "$all_images_list"

  if [ -d static/images ]; then
    ls -1 static/images/ > "$all_images_list"
  fi

  # 미사용 이미지 찾기 (all - used)
  unused_count=0
  deleted_count=0

  while IFS= read -r img_file; do
    # 사용 목록에 없으면 삭제
    if ! grep -qxF "$img_file" "$used_images_list"; then
      unused_count=$((unused_count + 1))

      # 실제 삭제
      if [ -f "static/images/$img_file" ]; then
        rm -f "static/images/$img_file"
        deleted_count=$((deleted_count + 1))
        echo "  🗑️  $img_file"
      fi
    fi
  done < "$all_images_list"

  # 임시 파일 삭제
  rm -f "$used_images_list" "$all_images_list"

  echo ""
  if [ "$deleted_count" -gt 0 ]; then
    echo "✅ $deleted_count 개의 unused 이미지 삭제 완료"
  else
    echo "ℹ️  삭제할 unused 이미지 없음"
  fi

  # 최종 통계
  remaining_images=$(ls -1 static/images/ 2>/dev/null | wc -l | tr -d ' ')
  echo "📸 남은 이미지: $remaining_images 개"
}

# 메인 로직
if [ "$FULL_SYNC" = true ]; then
  full_sync
else
  incremental_sync
fi

# 추가 이미지 복사 (혹시 놓친 것 처리)
echo ""
echo "📸 추가 이미지 확인 중..."
{
  # Markdown 이미지: ![alt](/images/filename)
  grep -oh '!\[[^]]*\](/images/[^)]*' content/posts/*.md content/*.md 2>/dev/null | sed 's|!\[[^]]*\](/images/||'
  # Hugo shortcode: {{< img src="/images/filename" >}}
  grep -oh 'src="/images/[^"]*"' content/posts/*.md content/*.md 2>/dev/null | sed 's|src="/images/||; s|"$||'
} | sort -u | while read encoded_img; do
  # Python으로 URL decode (한글, 특수문자 포함)
  img=$(python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]))" "$encoded_img")
  # static/images에 이미 있으면 건너뛰기
  if [ -f "static/images/$img" ]; then
    continue
  fi

  # vault의 assets 폴더에서 이미지 찾기
  found=$(find -L obsidian-vault -name "$img" 2>/dev/null | head -1)
  if [ -n "$found" ]; then
    cp "$found" "static/images/"
    echo "  ✓ $img"
  else
    echo "  ✗ $img (not found)"
  fi
done

echo ""
echo "✨ 동기화 완료!"
echo ""
echo "📝 발행된 글:"
post_count=$(ls -1 content/posts/*.md 2>/dev/null | wc -l)
page_count=$(ls -1 content/*.md 2>/dev/null | wc -l)
echo "  Posts: $post_count"
echo "  Pages: $page_count"
echo ""

# Unused 이미지 정리 (--clean-images 옵션)
if [ "$CLEAN_IMAGES" = true ]; then
  cleanup_unused_images
  echo ""
fi

# Git push 처리
if [ "$PUSH_TO_GIT" = true ]; then
  echo "🚀 Git push 시작..."
  echo ""

  # 변경사항 확인 (untracked 파일 포함)
  changes=$(git status --porcelain content/ static/images/ 2>/dev/null | wc -l | tr -d ' ')

  if [ "$changes" -eq 0 ]; then
    echo "ℹ️  변경사항 없음, push 건너뜀"
  else
    # 변경된 파일 개수 확인
    changed_posts=$(git status --porcelain content/posts/ 2>/dev/null | wc -l | tr -d ' ')
    changed_pages=$(git status --porcelain content/*.md 2>/dev/null | wc -l | tr -d ' ')
    changed_images=$(git status --porcelain static/images/ 2>/dev/null | wc -l | tr -d ' ')

    # 커밋 메시지 생성
    commit_summary="Sync blog"
    commit_details=""

    if [ "$changed_posts" -gt 0 ]; then
      commit_details="${commit_details}${changed_posts} post(s), "
    fi
    if [ "$changed_pages" -gt 0 ]; then
      commit_details="${commit_details}${changed_pages} page(s), "
    fi
    if [ "$changed_images" -gt 0 ]; then
      commit_details="${commit_details}${changed_images} image(s), "
    fi

    # 마지막 쉼표 제거
    commit_details=$(echo "$commit_details" | sed 's/, $//')

    if [ -n "$commit_details" ]; then
      commit_summary="Sync blog: $commit_details"
    fi

    # Git add, commit, push
    git add content/ static/images/

    git commit -m "$(cat <<EOF
$commit_summary

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

    echo ""
    echo "📤 Pushing to remote..."
    if git push; then
      echo ""
      echo "✅ Push 완료!"
      echo "🌐 배포 진행 중: https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/')/actions"
    else
      echo ""
      echo "❌ Push 실패"
      exit 1
    fi
  fi

  echo ""
fi
