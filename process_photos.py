#!/usr/bin/env python3
"""
AI & PM Research Hub — Photo Processor & Uploader
Matches photos to members, normalizes to 400x400 square, uploads to Supabase Storage.
"""

import os
import sys
import json
import re
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Installing Pillow...")
    os.system("pip install Pillow pillow-heif --break-system-packages -q")
    from PIL import Image

try:
    from supabase import create_client
except ImportError:
    print("Installing supabase...")
    os.system("pip install supabase --break-system-packages -q")
    from supabase import create_client

# Try HEIC support
try:
    from pillow_heif import register_heif_opener
    register_heif_opener()
    print("✓ HEIC support enabled")
except:
    print("⚠ HEIC support not available (Lorena's photo will be skipped)")

# ============================================================================
# CONFIG
# ============================================================================
SB_URL = 'https://ldrfrvwhxsmgaabwmaik.supabase.co'
SB_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxkcmZydndoeHNtZ2FhYndtYWlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI3MjU5NDQsImV4cCI6MjA4ODMwMTk0NH0.gzibKd7Jyck3Ya61vzrloX1YZt-0pNReTuefdi4mAmw'
PHOTOS_DIR = os.path.expanduser('~/Downloads/fotos')
OUTPUT_DIR = os.path.expanduser('~/Downloads/fotos_processed')
PHOTO_SIZE = 400  # 400x400 px
BUCKET_NAME = 'member-photos'

# ============================================================================
# PHOTO → MEMBER EMAIL MAPPING (manually verified)
# ============================================================================
PHOTO_MAP = {
    'Ana Cavalcante_líder de tribo.jpeg': 'anagatcavalcante@gmail.com',
    'Andressa Martins.jpeg': 'catoze@gmail.com',
    'Cintia Simoes.jpeg': 'cintia.simoes10@gmail.com',
    'Débora Moura_Líder de tribo.jpeg': 'debi.moura@gmail.com',
    'Denis Vasconcelos.jpg': 'queiroz_denis@hotmail.com',
    'Evilasio Lucena.jpg': 'evilasiolucena@gmail.com',
    'Fabricio Costa.jpg': 'fabriciorcc@gmail.com',
    'Fernando Maquiaveli_Líder de tribo.jpeg': 'fernando@maquiaveli.com.br',
    'Franze Oliveira.jpg': 'franze.n.oliveira@gmail.com',
    'Gustavo Batista.jpeg': 'eng.gustavobatista@gmail.com',
    'Hayala Curto_Líder de tribo.jpeg': 'hayala.curto@gmail.com',
    'Italo Nogueira.png': 'italo.sn@hotmail.com',
    'Jefferson Pinto_Líder de tribo.jpeg': 'jefferson.pinheiro.pinto@gmail.com',
    'João Coelho.png': 'j_coelho@id.uff.br',
    'Leandro Mota.png': 'leandro_mota@hotmail.com',
    'Leonardo Chaves.png': 'leonardo.grandinetti@gmail.com',
    'Leticia Clemente.jpeg': 'clementeleticia.lc@gmail.com',
    'Lídia do Vale.JPG': 'lidiadovalle@gmail.com',
    'Lorena Almeida.HEIC': 'loryalmeida13@icloud.com',
    'Luciana Dutra Martins.png': 'lucianadutramartins@outlook.com',
    'Marcel Fleming_Líder de tribo.jpeg': 'fleming.marcel@yahoo.com.br',
    'Marcos Antunes_Líder de tribo.jpeg': 'maklemz@gmail.com',
    'Marcos Moura Costa.jpeg': 'marcosmouracosta@gmail.com',
    'Maria Luiza.jpeg': 'malusilveirab@gmail.com',
    'Mauricio Abe.png': 'mauricio.abe.machado@gmail.com',
    'Mayanna Duarte.jpeg': 'mayanna.aires@gmail.com',
    'Paulo Alves.png': 'paulo-junior@outlook.com',
    'RODRIGO GRILO.png': 'rodrigo_ggomes@hotmail.com',
    'Vinicyus Saraiva.jpeg': 'vinicyus-saraiva@hotmail.com',
    'Vitor maia Rodovalho.jpeg': 'vitor.rodovalho@outlook.com',
    'wellinghton-pereira.jpeg': 'wbarbozaeng@gmail.com',
    # Not in current cycle 3 roster (archive):
    # 'Diego Menezes.jpg': None,
    # 'Lucas Vasconcelos.jpg': None,
    # 'Marcelo Ferreira Freitas Filho.jpeg': None,
    # 'Marcio Miranda.jpeg': None,
    # 'Roberto Macêdo.png': None,
    # 'Rogério Côrtes.png': None,
    # 'Sarah Rodovalho.jpg': None,
    # 'Werley Miranda.jpeg': None,
}

# ============================================================================
# STEP 1: Process photos (crop to square, resize, normalize)
# ============================================================================
def process_photos():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    processed = {}
    
    for filename, email in PHOTO_MAP.items():
        if email is None:
            continue
            
        filepath = os.path.join(PHOTOS_DIR, filename)
        if not os.path.exists(filepath):
            print(f"  ✗ Not found: {filename}")
            continue
        
        try:
            img = Image.open(filepath)
            
            # Convert to RGB (handles RGBA PNGs and CMYK)
            if img.mode in ('RGBA', 'P'):
                bg = Image.new('RGB', img.size, (255, 255, 255))
                if img.mode == 'P':
                    img = img.convert('RGBA')
                bg.paste(img, mask=img.split()[3])
                img = bg
            elif img.mode != 'RGB':
                img = img.convert('RGB')
            
            # Center crop to square
            w, h = img.size
            side = min(w, h)
            left = (w - side) // 2
            top = (h - side) // 2
            img = img.crop((left, top, left + side, top + side))
            
            # Resize to target size
            img = img.resize((PHOTO_SIZE, PHOTO_SIZE), Image.LANCZOS)
            
            # Save as JPEG with email-based filename
            safe_name = email.replace('@', '_at_').replace('.', '_') + '.jpg'
            output_path = os.path.join(OUTPUT_DIR, safe_name)
            img.save(output_path, 'JPEG', quality=85, optimize=True)
            
            processed[email] = {
                'local_path': output_path,
                'storage_name': safe_name,
                'original': filename
            }
            
            size_kb = os.path.getsize(output_path) / 1024
            print(f"  ✓ {filename} → {safe_name} ({size_kb:.0f}KB)")
            
        except Exception as e:
            print(f"  ✗ Error processing {filename}: {e}")
    
    return processed


# ============================================================================
# STEP 2: Upload to Supabase Storage + update member records
# ============================================================================
def upload_and_update(processed):
    sb = create_client(SB_URL, SB_KEY)
    
    # Check if bucket exists, create if not
    try:
        sb.storage.get_bucket(BUCKET_NAME)
        print(f"\n  Bucket '{BUCKET_NAME}' exists")
    except:
        print(f"\n  Creating bucket '{BUCKET_NAME}'...")
        sb.storage.create_bucket(BUCKET_NAME, options={"public": True})
        print(f"  ✓ Bucket created (public)")
    
    updated = 0
    for email, info in processed.items():
        try:
            # Upload file
            with open(info['local_path'], 'rb') as f:
                file_data = f.read()
            
            storage_path = f"avatars/{info['storage_name']}"
            
            # Try to remove existing file first (ignore errors)
            try:
                sb.storage.from_(BUCKET_NAME).remove([storage_path])
            except:
                pass
            
            sb.storage.from_(BUCKET_NAME).upload(
                storage_path,
                file_data,
                file_options={"content-type": "image/jpeg", "upsert": "true"}
            )
            
            # Get public URL
            photo_url = f"{SB_URL}/storage/v1/object/public/{BUCKET_NAME}/{storage_path}"
            
            # Update member record
            result = sb.table('members').update({'photo_url': photo_url}).eq('email', email).execute()
            
            if result.data:
                updated += 1
                print(f"  ✓ {email} → photo uploaded & linked")
            else:
                print(f"  ⚠ {email} → uploaded but member not found in DB")
                
        except Exception as e:
            print(f"  ✗ {email} → {e}")
    
    return updated


# ============================================================================
# MAIN
# ============================================================================
if __name__ == '__main__':
    print("=" * 60)
    print("  AI & PM Research Hub — Photo Processor")
    print("=" * 60)
    
    print(f"\n📁 Source: {PHOTOS_DIR}")
    print(f"📁 Output: {OUTPUT_DIR}")
    print(f"📐 Size: {PHOTO_SIZE}x{PHOTO_SIZE}px")
    print(f"🗄️  Bucket: {BUCKET_NAME}")
    
    # Step 1: Process
    print(f"\n[1/2] Processing photos...")
    processed = process_photos()
    print(f"\n  Processed: {len(processed)} of {len(PHOTO_MAP)} mapped photos")
    
    # Step 2: Upload
    print(f"\n[2/2] Uploading to Supabase Storage...")
    updated = upload_and_update(processed)
    
    print(f"\n{'=' * 60}")
    print(f"  Done! {updated} member photos updated in database.")
    print(f"  Photos are at: {SB_URL}/storage/v1/object/public/{BUCKET_NAME}/avatars/")
    print(f"{'=' * 60}")
