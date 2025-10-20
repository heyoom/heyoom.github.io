#!/usr/bin/env python3
"""
backup 폴더의 Markdown 파일 수정
- Obsidian 이미지 형식 → 일반 Markdown 형식
- HTML 태그 → Markdown 형식
"""

import glob
import os
import re


def fix_markdown_file(file_path):
    """MD 파일의 이미지 경로 및 태그 수정"""
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    original_content = content

    # 파일명에서 제목 부분 추출 (YYYY-MM-DD-제목.md)
    filename = os.path.basename(file_path)
    # 날짜 부분 제거 (YYYY-MM-DD-)
    title_part = re.sub(r'^\d{4}-\d{2}-\d{2}-', '', filename)
    # .md 제거
    title_part = title_part.replace('.md', '')

    # assets 경로
    assets_path = f'assets/{title_part}'

    # Obsidian 이미지 형식 → Markdown 이미지 형식
    # ![[filename]] → ![filename](assets/제목/filename)
    def replace_obsidian_image(match):
        img_name = match.group(1)
        return f'![{img_name}]({assets_path}/{img_name})'

    content = re.sub(r'!\[\[([^\]]+)\]\]', replace_obsidian_image, content)

    # HTML 태그 → Markdown 변환
    # <h2>...</h2> → ## ...
    content = re.sub(r'<h2[^>]*>(.*?)</h2>', r'## \1', content, flags=re.DOTALL)
    # <h3>...</h3> → ### ...
    content = re.sub(r'<h3[^>]*>(.*?)</h3>', r'### \1', content, flags=re.DOTALL)
    # <h4>...</h4> → #### ...
    content = re.sub(r'<h4[^>]*>(.*?)</h4>', r'#### \1', content, flags=re.DOTALL)

    # <strong>...</strong>, <b>...</b> → **...**
    content = re.sub(r'<strong>(.*?)</strong>', r'**\1**', content, flags=re.DOTALL)
    content = re.sub(r'<b>(.*?)</b>', r'**\1**', content, flags=re.DOTALL)

    # <em>...</em>, <i>...</i> → *...*
    content = re.sub(r'<em>(.*?)</em>', r'*\1*', content, flags=re.DOTALL)
    content = re.sub(r'<i>(.*?)</i>', r'*\1*', content, flags=re.DOTALL)

    # <a href="...">...</a> → [...](...)
    content = re.sub(r'<a href="([^"]+)"[^>]*>(.*?)</a>', r'[\2](\1)', content, flags=re.DOTALL)

    # 기타 HTML 태그 제거
    content = re.sub(r'<[^>]+>', '', content)

    # 불필요한 공백 정리
    content = re.sub(r'\n{3,}', '\n\n', content)

    # 파일이 변경되었으면 저장
    if content != original_content:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        return True

    return False


def main():
    backup_base = 'backup'

    # 모든 MD 파일 찾기
    md_files = glob.glob(f'{backup_base}/**/*.md', recursive=True)

    print(f"총 {len(md_files)}개 파일 수정 중...")

    modified_count = 0

    for i, md_file in enumerate(md_files, 1):
        try:
            if fix_markdown_file(md_file):
                modified_count += 1
                if modified_count % 10 == 0:
                    print(f"[{i}/{len(md_files)}] ✅ {modified_count}개 파일 수정 완료")
        except Exception as e:
            print(f"[{i}/{len(md_files)}] ❌ 오류: {md_file} - {e}")

    print(f"\n완료! 총 {modified_count}개 파일 수정")


if __name__ == '__main__':
    main()
