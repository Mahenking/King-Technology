#!/usr/bin/env python3
"""
King OS Repo Manager
Reads sources.txt, downloads packages, converts to .kpk, updates index.json
"""

import os
import sys
import json
import hashlib
import subprocess
import urllib.request
from datetime import datetime, UTC
from pathlib import Path

# Paths
REPO_ROOT = Path(__file__).parent.parent
SOURCES_FILE = REPO_ROOT / "sources.txt"
INDEX_FILE = REPO_ROOT / "index.json"
PACKAGES_DIR = REPO_ROOT / "packages"
TEMP_DIR = Path("/tmp/king-repo-temp")

PACKAGES_DIR.mkdir(parents=True, exist_ok=True)
TEMP_DIR.mkdir(parents=True, exist_ok=True)


def parse_sources():
    packages = []
    with open(SOURCES_FILE, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = [p.strip() for p in line.split('|')]
            if len(parts) < 5:
                print(f"⚠️  Line {line_num}: Skipping (need 5 fields)")
                continue
            packages.append({
                'name': parts[0],
                'version': parts[1],
                'url': parts[2],
                'arch': parts[3],
                'depends': [d.strip() for d in parts[4].split(',') if d.strip()],
                'description': parts[5] if len(parts) > 5 else '',
            })
    return packages


def load_index():
    default_index = {
        'version': '1.0',
        'generated': datetime.now(UTC).isoformat() + 'Z',
        'packages': {}
    }
    if INDEX_FILE.exists():
        try:
            with open(INDEX_FILE, 'r') as f:
                content = f.read().strip()
                if content:
                    data = json.loads(content)
                    if 'packages' not in data:
                        data['packages'] = {}
                    if 'version' not in data:
                        data['version'] = '1.0'
                    return data
        except (json.JSONDecodeError, ValueError):
            print("⚠️  index.json was corrupted — starting fresh")
    return default_index


def save_index(index):
    index['generated'] = datetime.now(UTC).isoformat() + 'Z'
    with open(INDEX_FILE, 'w') as f:
        json.dump(index, f, indent=2)
    print(f"✅ Index saved: {INDEX_FILE}")


def download_file(url, dest):
    print(f"   Downloading: {url}")
    try:
        urllib.request.urlretrieve(url, dest)
        size = os.path.getsize(dest)
        print(f"   ✅ Downloaded: {size:,} bytes")
        return True
    except Exception as e:
        print(f"   ❌ Download failed: {e}")
        return False


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b''):
            h.update(chunk)
    return h.hexdigest()


def convert_to_kpk(source_file, pkg_name, pkg_version, pkg_arch, output_path):
    print(f"   Converting to .kpk...")
    extract_dir = TEMP_DIR / f"{pkg_name}-{pkg_version}"
    subprocess.run(['rm', '-rf', str(extract_dir)])
    extract_dir.mkdir(parents=True, exist_ok=True)
    
    if source_file.endswith('.deb'):
        subprocess.run(['ar', 'x', str(source_file)], cwd=extract_dir, capture_output=True)
        for data_file in extract_dir.glob('data.tar.*'):
            if 'zst' in data_file.name:
                subprocess.run(['tar', '--use-compress-program=unzstd', '-xf', str(data_file)],
                              cwd=extract_dir, capture_output=True)
            elif 'xz' in data_file.name:
                subprocess.run(['tar', '-xJf', str(data_file)], cwd=extract_dir, capture_output=True)
            elif 'gz' in data_file.name:
                subprocess.run(['tar', '-xzf', str(data_file)], cwd=extract_dir, capture_output=True)
            data_file.unlink()
        for ctrl in extract_dir.glob('control.tar.*'):
            ctrl.unlink()
        deb_bin = extract_dir / 'debian-binary'
        if deb_bin.exists():
            deb_bin.unlink()
    
    elif '.tar.zst' in source_file:
        subprocess.run(['tar', '--use-compress-program=unzstd', '-xf', str(source_file)],
                      cwd=extract_dir, capture_output=True)
    elif '.tar.gz' in source_file:
        subprocess.run(['tar', '-xzf', str(source_file)], cwd=extract_dir, capture_output=True)
    else:
        print(f"   ❌ Unsupported format")
        return False
    
    manifest = {
        'name': pkg_name,
        'version': pkg_version,
        'arch': pkg_arch,
        'built_at': datetime.now(UTC).isoformat() + 'Z',
    }
    with open(extract_dir / 'manifest.json', 'w') as f:
        json.dump(manifest, f, indent=2)
    
    result = subprocess.run(
        ['tar', '--use-compress-program=zstd', '-cf', str(output_path), '-C', str(extract_dir), '.'],
        capture_output=True
    )
    if result.returncode != 0:
        print(f"   ❌ Packaging failed: {result.stderr.decode()}")
        return False
    
    subprocess.run(['rm', '-rf', str(extract_dir)])
    print(f"   ✅ Created: {output_path.name}")
    return True


def main():
    print("=" * 60)
    print("  King OS Repo Manager")
    print("=" * 60)
    
    if not SOURCES_FILE.exists():
        print(f"❌ sources.txt not found: {SOURCES_FILE}")
        sys.exit(1)
    
    packages = parse_sources()
    print(f"\n📦 Found {len(packages)} packages in sources.txt\n")
    
    index = load_index()
    updated, skipped, failed = 0, 0, 0
    
    for pkg in packages:
        print(f"\n🔷 {pkg['name']} ({pkg['version']})")
        
        existing = index['packages'].get(pkg['name'])
        if existing and existing['version'] == pkg['version']:
            print(f"   ⏭️  Already in repo (same version)")
            skipped += 1
            continue
        
        # Determine extension
        ext = '.deb'
        if '.tar.zst' in pkg['url']:
            ext = '.tar.zst'
        elif '.tar.gz' in pkg['url']:
            ext = '.tar.gz'
        
        filename = f"{pkg['name']}-{pkg['version']}-{pkg['arch']}"
        download_path = TEMP_DIR / f"{filename}{ext}"
        
        if not download_file(pkg['url'], download_path):
            failed += 1
            continue
        
        kpk_path = PACKAGES_DIR / f"{filename}.kpk"
        if not convert_to_kpk(str(download_path), pkg['name'], pkg['version'], pkg['arch'], kpk_path):
            failed += 1
            continue
        
        sha = sha256_file(kpk_path)
        size = os.path.getsize(kpk_path)
        print(f"   ✅ SHA256: {sha[:16]}...")
        
        index['packages'][pkg['name']] = {
            'version': pkg['version'],
            'arch': pkg['arch'],
            'filename': f"packages/{filename}.kpk",
            'sha256': sha,
            'size': size,
            'depends': pkg['depends'],
            'description': pkg['description'],
            'date_added': datetime.now(UTC).strftime('%Y-%m-%d'),
            'reboot_required': False,
        }
        download_path.unlink()
        updated += 1
    
    save_index(index)
    print("\n" + "=" * 60)
    print(f"✅ Updated: {updated}  |  Skipped: {skipped}  |  Failed: {failed}")
    print(f"   Total in index: {len(index['packages'])}")
    print("=" * 60)


if __name__ == '__main__':
    main()
