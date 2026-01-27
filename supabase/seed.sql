CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 1. Create a System User
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = '00000000-0000-0000-0000-000000000000') THEN
        INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, role, raw_app_meta_data, raw_user_meta_data)
        VALUES (
            '00000000-0000-0000-0000-000000000000', 
            'system_owner@example.com', 
            extensions.crypt('seed_password_123', extensions.gen_salt('bf')),
            now(), 
            'authenticated',
            '{"provider":"email","providers":["email"]}',
            '{"name": "System Owner"}'
        );
    END IF;
END $$;

-- 2. Seed Bravo Table
INSERT INTO
    public.bravo (id, user_id, bravo_1, bravo_2)
VALUES (
        'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d',
        '00000000-0000-0000-0000-000000000000',
        'bravo_one',
        'bravo_one_description'
    ),
    (
        'b2c3d4e5-f6a7-4b6c-9d0e-1f2a3b4c5d6e',
        '00000000-0000-0000-0000-000000000000',
        'bravo_two',
        'bravo_two_description'
    ),
    (
        'c3d4e5f6-a7b8-4c7d-0e1f-2a3b4c5d6e7f',
        '00000000-0000-0000-0000-000000000000',
        'bravo_three',
        'bravo_three_description'
    )
ON CONFLICT (id) DO NOTHING;

-- 3. Seed Storage Objects (The "Files")
-- This tells Supabase these files exist in the 'alfa_assets' bucket
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

-- 4. Seed Alfa Table (with image URLs)
-- We construct the URL based on your project structure: 
-- /storage/v1/object/public/[bucket_name]/[file_name]
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
        'john_doe.png'
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
        NULL
    ),
    (
        'Bob',
        'Brown',
        'c3d4e5f6-a7b8-4c7d-0e1f-2a3b4c5d6e7f',
        NULL
    ),
    (
        'Charlie',
        'Davis',
        'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d',
        NULL
    )
ON CONFLICT DO NOTHING;