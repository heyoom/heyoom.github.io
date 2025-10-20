#!/usr/bin/env python3
"""
티스토리 백업 HTML을 Markdown으로 변환
- 러닝/기록: 옵시디언 B.Area/러닝/기록 폴더로
- 나머지: backup 폴더에 카테고리 구조로
"""

import glob
import os
import re
import shutil
from datetime import datetime
from pathlib import Path
from html.parser import HTMLParser
from html import unescape

class HTMLToMarkdown(HTMLParser):
    def __init__(self):
        super().__init__()
        self.markdown = []
        self.current_tag = None

    def handle_starttag(self, tag, attrs):
        self.current_tag = tag

    def handle_data(self, data):
        if self.current_tag and data.strip():
            self.markdown.append(data.strip())

    def get_markdown(self):
        return '\n\n'.join(self.markdown)


def extract_post_data(html_file):
    """HTML 파일에서 메타데이터와 본문 추출"""
    with open(html_file, 'r', encoding='utf-8') as f:
        content = f.read()

    # 제목
    title_match = re.search(r'<h2 class="title-article">([^<]+)</h2>', content)
    title = title_match.group(1) if title_match else "제목 없음"

    # 카테고리
    category_match = re.search(r'<p class="category">([^<]+)</p>', content)
    category = category_match.group(1) if category_match else "분류 없음"

    # 날짜
    date_match = re.search(r'<p class="date">([^<]+)</p>', content)
    date_str = date_match.group(1) if date_match else ""

    # 본문 (contents_style div 내용)
    body_match = re.search(r'<div class="contents_style">(.*?)</div>', content, re.DOTALL)
    body_html = body_match.group(1) if body_match else ""

    # 태그
    tags_match = re.search(r'<div class="tags">(.*?)</div>', content, re.DOTALL)
    tags_str = tags_match.group(1) if tags_match else ""
    tags = [tag.strip().replace('#', '') for tag in tags_str.split() if tag.strip().startswith('#')]

    return {
        'title': title,
        'category': category,
        'date': date_str,
        'body_html': body_html,
        'tags': tags,
        'html_file': html_file
    }


def html_to_markdown(html_str, img_folder, image_format='obsidian', assets_path='', date_prefix=''):
    """HTML을 간단한 Markdown으로 변환

    Args:
        html_str: HTML 문자열
        img_folder: 이미지 폴더 경로
        image_format: 'obsidian' (![[file]]) 또는 'markdown' (![](path))
        assets_path: markdown 형식일 때 사용할 assets 경로
        date_prefix: 이미지 파일명 prefix (예: 2025-09-17)
    """
    # h2, h3, h4 태그를 Markdown으로 변환
    html_str = re.sub(r'<h2[^>]*>(.*?)</h2>', r'\n\n## \1\n\n', html_str, flags=re.DOTALL)
    html_str = re.sub(r'<h3[^>]*>(.*?)</h3>', r'\n\n### \1\n\n', html_str, flags=re.DOTALL)
    html_str = re.sub(r'<h4[^>]*>(.*?)</h4>', r'\n\n#### \1\n\n', html_str, flags=re.DOTALL)

    # figure/img 태그를 Markdown 이미지로 변환
    def replace_image(match):
        src = match.group(1)
        if src.startswith('./img/'):
            filename = os.path.basename(src)
            # 날짜 prefix를 붙인 새 파일명
            if date_prefix:
                new_filename = f"{date_prefix}-{filename}"
            else:
                new_filename = filename

            if image_format == 'obsidian':
                return f'![[{new_filename}]]'
            else:  # markdown
                return f'![{new_filename}]({assets_path}/{new_filename})'
        return ''

    html_str = re.sub(r'<img[^>]+src="([^"]+)"[^>]*>', replace_image, html_str)

    # figure 태그 제거
    html_str = re.sub(r'</?figure[^>]*>', '', html_str)
    html_str = re.sub(r'</?span[^>]*>', '', html_str)
    html_str = re.sub(r'</?figcaption[^>]*>', '', html_str)

    # p 태그를 줄바꿈으로
    html_str = re.sub(r'<p[^>]*>', '', html_str)
    html_str = re.sub(r'</p>', '\n\n', html_str)

    # br 태그를 줄바꿈으로
    html_str = re.sub(r'<br\s*/?>', '\n', html_str)

    # 나머지 HTML 태그 제거
    html_str = re.sub(r'<[^>]+>', '', html_str)

    # HTML 엔티티 디코드
    html_str = unescape(html_str)

    # 불필요한 공백 정리
    html_str = re.sub(r'\n{3,}', '\n\n', html_str)
    html_str = re.sub(r' +', ' ', html_str)
    html_str = html_str.strip()

    return html_str


def convert_running_record(post_data, obsidian_path):
    """러닝/기록을 옵시디언 형식으로 변환"""
    # 날짜 파싱
    date_match = re.search(r'(\d{4})[.-](\d{2})[.-](\d{2})', post_data['date'])
    if not date_match:
        # 제목에서 날짜 추출 시도
        date_match = re.search(r'(\d{4})[.-](\d{2})[.-](\d{2})', post_data['title'])

    if not date_match:
        print(f"날짜를 파싱할 수 없음: {post_data['html_file']}")
        return None

    year, month, day = date_match.groups()
    date_str = f"{year}-{month}-{day}"
    filename = f"{date_str}.md"

    # 이미지 폴더 확인
    html_dir = os.path.dirname(post_data['html_file'])
    img_folder = os.path.join(html_dir, 'img')

    # 본문 변환 (Obsidian 형식, 날짜 prefix 포함)
    body_md = html_to_markdown(post_data['body_html'], img_folder,
                                image_format='obsidian', date_prefix=date_str)

    # frontmatter 생성
    frontmatter = f"""---
tags:
"""
    for tag in post_data['tags']:
        frontmatter += f"  - {tag}\n"

    frontmatter += f"""created: {post_data['date']}
updated: {post_data['date']}
published: true
categories:
  - 러닝
  - 기록
---

"""

    # 전체 내용
    content = frontmatter + body_md

    # 파일 저장
    output_file = os.path.join(obsidian_path, filename)

    # 파일이 이미 존재하면 덮어쓰기 확인
    if os.path.exists(output_file):
        print(f"⚠️  이미 존재: {filename} (건너뜀)")
        return None

    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(content)

    # 이미지 복사 (날짜 prefix를 붙인 파일명으로)
    if os.path.exists(img_folder):
        assets_folder = os.path.join(obsidian_path, 'assets')
        os.makedirs(assets_folder, exist_ok=True)

        for img_file in glob.glob(os.path.join(img_folder, '*')):
            original_filename = os.path.basename(img_file)
            new_filename = f"{date_str}-{original_filename}"
            dest_path = os.path.join(assets_folder, new_filename)
            shutil.copy2(img_file, dest_path)

    return output_file


def convert_normal_post(post_data, backup_base):
    """일반 글을 backup 폴더로 변환"""
    # 카테고리 폴더 생성
    category = post_data['category'].replace('/', '_')
    category_folder = os.path.join(backup_base, category)
    os.makedirs(category_folder, exist_ok=True)

    # 파일명: 제목에서 생성 (날짜 포함)
    date_match = re.search(r'(\d{4})-(\d{2})-(\d{2})', post_data['date'])
    if date_match:
        date_prefix = date_match.group(0)
    else:
        date_prefix = "0000-00-00"

    # 안전한 파일명 생성
    safe_title = re.sub(r'[^\w\s-]', '', post_data['title'])
    safe_title = re.sub(r'[-\s]+', '-', safe_title)
    safe_title = safe_title[:50]  # 길이 제한

    filename = f"{date_prefix}-{safe_title}.md"

    # 이미지 폴더 확인
    html_dir = os.path.dirname(post_data['html_file'])
    img_folder = os.path.join(html_dir, 'img')

    # 본문 변환 (일반 마크다운 형식, assets 경로 포함)
    assets_path = f'assets'
    body_md = html_to_markdown(post_data['body_html'], img_folder,
                                image_format='markdown', assets_path=assets_path,
                                date_prefix=date_prefix)

    # frontmatter 생성
    frontmatter = f"""---
title: "{post_data['title']}"
date: {post_data['date']}
category: {post_data['category']}
tags:
"""
    for tag in post_data['tags']:
        frontmatter += f"  - {tag}\n"

    frontmatter += """---

"""

    # 전체 내용
    content = frontmatter + body_md

    # 파일 저장
    output_file = os.path.join(category_folder, filename)
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(content)

    # 이미지 복사 (날짜 prefix를 붙인 파일명으로)
    if os.path.exists(img_folder):
        assets_folder = os.path.join(category_folder, 'assets')
        os.makedirs(assets_folder, exist_ok=True)

        for img_file in glob.glob(os.path.join(img_folder, '*')):
            original_filename = os.path.basename(img_file)
            new_filename = f"{date_prefix}-{original_filename}"
            dest_path = os.path.join(assets_folder, new_filename)
            shutil.copy2(img_file, dest_path)

    return output_file


def main():
    # 경로 설정
    backup_dir = 'minorlab-tistory-backup'
    obsidian_running = '/Users/heyoom/Library/Mobile Documents/iCloud~md~obsidian/Documents/Danny_iCloud/B.Area/러닝/기록'
    backup_base = 'backup'

    # 백업 폴더 생성
    os.makedirs(backup_base, exist_ok=True)

    # 모든 HTML 파일 처리
    html_files = glob.glob(f'{backup_dir}/*/*.html')

    print(f"총 {len(html_files)}개 파일 발견")

    running_count = 0
    normal_count = 0
    error_count = 0

    for i, html_file in enumerate(html_files, 1):
        try:
            post_data = extract_post_data(html_file)

            if post_data['category'] == '러닝/기록':
                # 러닝 기록은 이미 처리되어 있으므로 건너뜀
                if i % 50 == 0:
                    print(f"[{i}/{len(html_files)}] ⏭️  러닝: 건너뜀")
                continue
            else:
                result = convert_normal_post(post_data, backup_base)
                normal_count += 1
                if i % 10 == 0:
                    print(f"[{i}/{len(html_files)}] 📝 일반: {post_data['category']} - {normal_count}개 완료")

        except Exception as e:
            error_count += 1
            print(f"[{i}/{len(html_files)}] ❌ 오류: {html_file} - {e}")

    print(f"\n완료!")
    print(f"  러닝/기록: {running_count}개")
    print(f"  일반 글: {normal_count}개")
    print(f"  오류: {error_count}개")


if __name__ == '__main__':
    main()
