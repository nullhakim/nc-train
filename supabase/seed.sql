CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 1. Create a System User to own these seed records
-- This UUID is arbitrary but consistent for seeding
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

-- 2. Seed Bravo Table (using your specific IDs)
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

-- 3. Seed Alfa Table
INSERT INTO
    public.alfa (alfa_1, alfa_2, bravo_id)
VALUES (
        'John',
        'Doe',
        'c3d4e5f6-a7b8-4c7d-0e1f-2a3b4c5d6e7f'
    ),
    (
        'Jane',
        'Smith',
        'b2c3d4e5-f6a7-4b6c-9d0e-1f2a3b4c5d6e'
    ),
    (
        'Alice',
        'Johnson',
        'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d'
    ),
    (
        'Bob',
        'Brown',
        'c3d4e5f6-a7b8-4c7d-0e1f-2a3b4c5d6e7f'
    ),
    (
        'Charlie',
        'Davis',
        'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d'
    )
ON CONFLICT DO NOTHING;