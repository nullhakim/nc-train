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

-- 2. Create Alfa Table (The Child)
CREATE TABLE public.alfa (
    id uuid DEFAULT gen_random_uuid () PRIMARY KEY,
    alfa_1 VARCHAR(100) NOT NULL,
    alfa_2 VARCHAR(100),
    bravo_id uuid NOT NULL,
    CONSTRAINT fk_bravo FOREIGN KEY (bravo_id) REFERENCES public.bravo (id) ON DELETE CASCADE
);

-- 3. Enable RLS
ALTER TABLE public.bravo ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.alfa ENABLE ROW LEVEL SECURITY;

-- Everyone (logged in or not) can view Bravo records
CREATE POLICY "Allow read access to all users" ON public.bravo FOR
SELECT TO public USING (true);

-- Only authenticated users can insert (their own ID is set by default)
CREATE POLICY "Allow insert access to authenticated users" ON public.bravo FOR INSERT TO authenticated
WITH
    CHECK (auth.uid () = user_id);

-- Only the owner can update or delete their Bravo records
CREATE POLICY "Allow update and delete access to owner only" ON public.bravo FOR ALL TO authenticated USING (auth.uid () = user_id)
WITH
    CHECK (auth.uid () = user_id);

-- Everyone (logged in or not) can view Alfa records
CREATE POLICY "Allow read access to all users" ON public.alfa FOR
SELECT TO public USING (true);

-- Only authenticated users can insert Alfa records
CREATE POLICY "Allow insert access to authenticated users" ON public.alfa FOR ALL TO authenticated USING (
    EXISTS (
        SELECT 1
        FROM public.bravo
        WHERE
            bravo.id = alfa.bravo_id
            AND bravo.user_id = auth.uid ()
    )
)
WITH
    CHECK (
        EXISTS (
            SELECT 1
            FROM public.bravo
            WHERE
                bravo.id = alfa.bravo_id
                AND bravo.user_id = auth.uid ()
        )
    );

ALTER PUBLICATION supabase_realtime
ADD TABLE public.bravo,
public.alfa;