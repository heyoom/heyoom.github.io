#!/usr/bin/env python3
"""
깨진 이미지 링크가 있는 md 문서 목록 출력
"""
import os
import re
import urllib.parse
from pathlib import Path
from collections import defaultdict

VAULT_PATH = Path("/Users/heyoom/Documents/obsidian")
TRASH_PATH = VAULT_PATH / ".trash"
EXCLUDE_DIRS = ["D.Archive", ".trash"]

IMAGE_EXTENSIONS = {'.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp',
                   '.heic', '.avif', '.bmp', '.tiff', '.ico', '.pdf',
                   '.ttf', '.base', '.txt'}

def find_all_md_files():
    """D.Archive와 .trash를 제외한 모든 md 파일 찾기"""
    md_files = []
    for root, dirs, files in os.walk(VAULT_PATH):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for file in files:
            if file.endswith('.md'):
                md_files.append(Path(root) / file)
    return md_files

def extract_image_references(md_file):
    """md 파일에서 이미지 참조 추출"""
    images = []
    try:
        with open(md_file, 'r', encoding='utf-8') as f:
            content = f.read()
        pattern = r'!\[\[([^\]|]+)(?:\|[^\]]*)?\]\]'
        matches = re.findall(pattern, content)
        for match in matches:
            try:
                decoded = urllib.parse.unquote(match)
                images.append(decoded)
            except:
                images.append(match)
    except Exception as e:
        print(f"Error reading {md_file}: {e}")
    return images

def find_image_in_assets(image_name):
    """모든 assets 폴더에서 이미지 찾기"""
    for root, dirs, files in os.walk(VAULT_PATH):
        if 'assets' in dirs:
            assets_path = Path(root) / 'assets'
            image_path = assets_path / image_name
            if image_path.exists():
                return image_path
    return None

def main():
    print("깨진 이미지 링크가 있는 문서 확인 중...\n")

    md_files = find_all_md_files()

    # 문서별로 깨진 이미지 수집
    broken_by_doc = defaultdict(list)

    for md_file in md_files:
        images = extract_image_references(md_file)
        for img in images:
            if not img.startswith('http'):
                ext = Path(img).suffix.lower()
                if ext in IMAGE_EXTENSIONS:
                    if not find_image_in_assets(img):
                        broken_by_doc[md_file].append(img)

    # 결과 출력
    if not broken_by_doc:
        print("✅ 깨진 이미지 링크가 없습니다!")
        return

    print(f"📄 깨진 이미지가 있는 문서: {len(broken_by_doc)}개\n")
    print("=" * 80)

    # 문서별로 출력 (경로 정렬)
    for md_file in sorted(broken_by_doc.keys()):
        rel_path = md_file.relative_to(VAULT_PATH)
        broken_images = broken_by_doc[md_file]

        print(f"\n📝 {rel_path}")
        print(f"   깨진 이미지: {len(broken_images)}개")
        for img in broken_images:
            print(f"   ❌ {img}")

    print("\n" + "=" * 80)
    print(f"총 {len(broken_by_doc)}개 문서에서 {sum(len(imgs) for imgs in broken_by_doc.values())}개 깨진 링크 발견")

if __name__ == "__main__":
    main()
