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

CREATE TABLE public.bravo (
    id uuid DEFAULT gen_random_uuid () PRIMARY KEY,
    bravo_1 VARCHAR(100) NOT NULL,
    bravo_2 VARCHAR(100)
);

CREATE TABLE public.alfa (
    id uuid DEFAULT gen_random_uuid () PRIMARY KEY,
    alfa_1 VARCHAR(100) NOT NULL,
    alfa_2 VARCHAR(100),
    bravo_id uuid,
    CONSTRAINT fk_bravo FOREIGN KEY (bravo_id) REFERENCES public.bravo (id) ON DELETE SET NULL
);