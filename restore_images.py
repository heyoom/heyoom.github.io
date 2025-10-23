#!/usr/bin/env python3
"""
옵시디언 문서에서 참조된 이미지가 assets에 없으면 .trash에서 복원하는 스크립트
"""
import os
import re
import shutil
import urllib.parse
from pathlib import Path
from collections import defaultdict

VAULT_PATH = Path("/Users/heyoom/Documents/obsidian")
TRASH_PATH = VAULT_PATH / ".trash"
EXCLUDE_DIRS = ["D.Archive", ".trash"]

def find_all_md_files():
    """D.Archive와 .trash를 제외한 모든 md 파일 찾기"""
    md_files = []
    for root, dirs, files in os.walk(VAULT_PATH):
        # D.Archive, .trash 제외
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

        # ![[이미지.png]], ![[이미지.png|설명]] 형식 찾기
        pattern = r'!\[\[([^\]|]+)(?:\|[^\]]*)?\]\]'
        matches = re.findall(pattern, content)

        for match in matches:
            # URL 디코딩
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

def find_image_in_trash(image_name):
    """trash 폴더에서 이미지 찾기"""
    if not TRASH_PATH.exists():
        return None

    # 정확한 파일명으로 찾기
    image_path = TRASH_PATH / image_name
    if image_path.exists():
        return image_path

    # URL 인코딩된 버전으로 찾기
    encoded_name = urllib.parse.quote(image_name)
    image_path = TRASH_PATH / encoded_name
    if image_path.exists():
        return image_path

    return None

def restore_image(image_name, target_dir):
    """trash에서 이미지를 target_dir로 복원"""
    trash_image = find_image_in_trash(image_name)

    if not trash_image:
        return False

    target_path = target_dir / image_name

    try:
        shutil.copy2(trash_image, target_path)
        print(f"✅ 복원: {image_name} -> {target_path}")
        return True
    except Exception as e:
        print(f"❌ 복원 실패: {image_name} - {e}")
        return False

def main():
    print("옵시디언 이미지 복원 시작...")
    print(f"Vault: {VAULT_PATH}")
    print(f"Trash: {TRASH_PATH}")
    print()

    # 1. 모든 md 파일 찾기
    print("📄 md 파일 검색 중...")
    md_files = find_all_md_files()
    print(f"   {len(md_files)}개 파일 발견")
    print()

    # 2. 모든 이미지 참조 수집
    print("🖼️  이미지 참조 추출 중...")
    all_images = set()
    image_to_md = defaultdict(list)

    # 이미지 확장자 목록
    IMAGE_EXTENSIONS = {'.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp',
                       '.heic', '.avif', '.bmp', '.tiff', '.ico', '.pdf',
                       '.ttf', '.base', '.txt'}

    for md_file in md_files:
        images = extract_image_references(md_file)
        for img in images:
            # 파일 확장자가 있는 것만 (링크 제외)
            if not img.startswith('http'):
                # 이미지 확장자 체크
                ext = Path(img).suffix.lower()
                if ext in IMAGE_EXTENSIONS:
                    all_images.add(img)
                    image_to_md[img].append(md_file)

    print(f"   {len(all_images)}개 고유 이미지 참조 발견")
    print()

    # 3. 누락된 이미지 확인
    print("🔍 누락된 이미지 확인 중...")
    missing_images = []

    for image in all_images:
        if not find_image_in_assets(image):
            missing_images.append(image)

    print(f"   {len(missing_images)}개 이미지 누락")
    print()

    if not missing_images:
        print("✅ 모든 이미지가 assets에 존재합니다!")
        return

    # 4. trash에서 복원
    print("♻️  trash에서 복원 시도 중...")
    restored = 0
    not_found = []

    # 기본 assets 폴더 (C.Resource/기타/assets 사용)
    default_assets = VAULT_PATH / "C.Resource" / "기타" / "assets"
    if not default_assets.exists():
        default_assets.mkdir(parents=True)

    for image in missing_images:
        if restore_image(image, default_assets):
            restored += 1
            print(f"   참조 위치: {', '.join([str(f.relative_to(VAULT_PATH)) for f in image_to_md[image][:3]])}")
        else:
            not_found.append(image)

    print()
    print("=" * 60)
    print(f"복원 완료: {restored}개")
    print(f"찾을 수 없음: {len(not_found)}개")

    if not_found:
        print()
        print("❌ 다음 이미지를 찾을 수 없습니다:")
        for img in not_found[:20]:  # 최대 20개만 표시
            print(f"   - {img}")
            md_files = image_to_md[img]
            print(f"     사용처: {md_files[0].relative_to(VAULT_PATH)}")

        if len(not_found) > 20:
            print(f"   ... 외 {len(not_found) - 20}개")

if __name__ == "__main__":
    main()
