-- ==========================================
-- 1. SETUP EXTENSIONS
-- ==========================================
-- Kita butuh pgcrypto untuk menghitung hash password user baru
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ==========================================
-- 2. CREATE SYSTEM USER (The Owner)
-- ==========================================
-- Kita buat user "spesial" dengan ID nol semua agar gampang diingat
-- dan bisa direferensikan oleh tabel lain secara konsisten.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = '00000000-0000-0000-0000-000000000000') THEN
        INSERT INTO auth.users (
            id, 
            email, 
            encrypted_password, 
            email_confirmed_at, 
            role, 
            raw_app_meta_data, 
            raw_user_meta_data
        )
        VALUES (
            '00000000-0000-0000-0000-000000000000', 
            'system_owner@example.com', 
            -- Password di-hash menggunakan blowfish (bf)
            extensions.crypt('seed_password_123', extensions.gen_salt('bf')),
            now(), 
            'authenticated',
            '{"provider":"email","providers":["email"]}',
            '{"name": "System Owner"}'
        );
    END IF;
END $$;

-- ==========================================
-- 3. SEED BRAVO TABLE (Parent Data)
-- ==========================================
-- Mengisi data induk yang dimiliki oleh System Owner.
INSERT INTO
    public.bravo (id, user_id, bravo_1, bravo_2)
VALUES (
        'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d',
        '00000000-0000-0000-0000-000000000000',
        'Bravo Group Alpha',
        'Kategori utama untuk aset foto'
    ),
    (
        'b2c3d4e5-f6a7-4b6c-9d0e-1f2a3b4c5d6e',
        '00000000-0000-0000-0000-000000000000',
        'Bravo Group Beta',
        'Kategori sekunder'
    ),
    (
        'c3d4e5f6-a7b8-4c7d-0e1f-2a3b4c5d6e7f',
        '00000000-0000-0000-0000-000000000000',
        'Bravo Group Gamma',
        'Kategori arsip'
    )
ON CONFLICT (id) DO NOTHING;

-- ==========================================
-- 4. SEED STORAGE OBJECTS (File Metadata)
-- ==========================================
-- PENTING: Ini hanya memasukkan "catatan" ke database bahwa file itu ADA.
-- File fisiknya sendiri diunggah lewat script Node.js (seed-storage).
INSERT INTO
    storage.objects (
        id,
        bucket_id,
        name,
        owner,
        metadata
    )
VALUES (
        gen_random_uuid (),
        'alfa_assets',
        'john_doe.png',
        '00000000-0000-0000-0000-000000000000',
        '{"mimetype": "image/png"}'
    ),
    (
        gen_random_uuid (),
        'alfa_assets',
        'jane_smith.png',
        '00000000-0000-0000-0000-000000000000',
        '{"mimetype": "image/png"}'
    )
ON CONFLICT DO NOTHING;

-- ==========================================
-- 5. SEED ALFA TABLE (Child Data)
-- ==========================================
-- Menghubungkan data orang dengan grup (Bravo) dan fotonya (Storage).
INSERT INTO
    public.alfa (
        alfa_1,
        alfa_2,
        bravo_id,
        image_url
    )
VALUES (
        'John',
        'Doe',
        'c3d4e5f6-a7b8-4c7d-0e1f-2a3b4c5d6e7f',
        'john_doe.png' -- Nama file harus sama dengan di storage.objects
    ),
    (
        'Jane',
        'Smith',
        'b2c3d4e5-f6a7-4b6c-9d0e-1f2a3b4c5d6e',
        'jane_smith.png'
    ),
    (
        'Alice',
        'Johnson',
        'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d',
        NULL -- Contoh data tanpa foto
    )
ON CONFLICT DO NOTHING;