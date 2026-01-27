DO $$ 
DECLARE
    r RECORD;
BEGIN
    -- We filter for 'r' (base tables) to avoid trying to drop views or foreign tables
    FOR r IN (
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public'
    ) LOOP
        -- Using format() is cleaner and safer than string concatenation
        EXECUTE format('DROP TABLE IF EXISTS public.%I CASCADE', r.tablename);
    END LOOP;
END $$;

-- 1. Create Bravo Table (The Parent)
CREATE TABLE public.bravo (
    id uuid DEFAULT gen_random_uuid () PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users (id) DEFAULT auth.uid (),
    bravo_1 VARCHAR(100) NOT NULL,
    bravo_2 VARCHAR(100)
);

-- 2. Create Alfa Table (Added image_url)
CREATE TABLE public.alfa (
    id uuid DEFAULT gen_random_uuid () PRIMARY KEY,
    alfa_1 VARCHAR(100) NOT NULL,
    alfa_2 VARCHAR(100),
    bravo_id uuid NOT NULL,
    image_url TEXT,
    CONSTRAINT fk_bravo FOREIGN KEY (bravo_id) REFERENCES public.bravo (id) ON DELETE CASCADE
);

-- 3. Storage Setup: Create Bucket
-- Note: inserting into storage.buckets requires permissions usually held by the migration runner
INSERT INTO
    storage.buckets (id, name, public)
VALUES (
        'alfa_assets',
        'alfa_assets',
        true
    )
ON CONFLICT (id) DO NOTHING;

-- 4. Enable RLS
ALTER TABLE public.bravo ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.alfa ENABLE ROW LEVEL SECURITY;

-- Bravo Policies
CREATE POLICY "Allow read access to all users" ON public.bravo FOR
SELECT TO public USING (true);

CREATE POLICY "Allow insert access to authenticated users" ON public.bravo FOR INSERT TO authenticated
WITH
    CHECK (auth.uid () = user_id);

CREATE POLICY "Allow update and delete access to owner only" ON public.bravo FOR ALL TO authenticated USING (auth.uid () = user_id);

-- Alfa Policies
CREATE POLICY "Allow read access to all users" ON public.alfa FOR
SELECT TO public USING (true);

CREATE POLICY "Allow owner to manage Alfa" ON public.alfa FOR ALL TO authenticated USING (
    EXISTS (
        SELECT 1
        FROM public.bravo
        WHERE
            bravo.id = alfa.bravo_id
            AND bravo.user_id = auth.uid ()
    )
);

---
-- STORAGE POLICIES
---

-- Allow public to view images
CREATE POLICY "Allow public read access to alfa_assets" ON storage.objects FOR
SELECT TO public USING (bucket_id = 'alfa_assets');

-- Allow authenticated users to upload images
CREATE POLICY "Allow authenticated users to upload to alfa_assets" ON storage.objects FOR INSERT TO authenticated
WITH
    CHECK (bucket_id = 'alfa_assets');

-- Allow users to delete images they "own" via the relationship to bravo
CREATE POLICY "Allow users to delete their own alfa_assets" ON storage.objects FOR DELETE TO authenticated USING (
    bucket_id = 'alfa_assets'
    AND EXISTS (
        SELECT 1
        FROM public.alfa a
            JOIN public.bravo b ON a.bravo_id = b.id
        WHERE
            b.user_id = auth.uid ()
            AND a.image_url LIKE '%' || name || '%'
    )
);

ALTER PUBLICATION supabase_realtime
ADD TABLE public.bravo,
public.alfa;