-- ==========================================
-- 1. CLEANUP: Reset Public Schema (Dev Only)
-- ==========================================
-- Menghapus semua tabel yang ada di skema public agar migrasi mulai dari nol.
DO $$ 
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public'
    ) LOOP
        EXECUTE format('DROP TABLE IF EXISTS public.%I CASCADE', r.tablename);
    END LOOP;
END $$;

-- ==========================================
-- 2. TABLES: Bravo (Parent) & Alfa (Child)
-- ==========================================

-- Tabel Bravo: Tabel utama milik user
CREATE TABLE public.bravo (
    id uuid DEFAULT gen_random_uuid () PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users (id) DEFAULT auth.uid (),
    bravo_1 VARCHAR(100) NOT NULL,
    bravo_2 VARCHAR(100)
);

-- Tabel Alfa: Tabel anak yang menyimpan referensi gambar
CREATE TABLE public.alfa (
    id uuid DEFAULT gen_random_uuid () PRIMARY KEY,
    alfa_1 VARCHAR(100) NOT NULL,
    alfa_2 VARCHAR(100),
    bravo_id uuid NOT NULL,
    image_url TEXT, -- Menyimpan nama file (misal: "foto.png")
    CONSTRAINT fk_bravo FOREIGN KEY (bravo_id) REFERENCES public.bravo (id) ON DELETE CASCADE
);

-- ==========================================
-- 3. STORAGE: Bucket Setup
-- ==========================================

-- Membuat bucket untuk menyimpan aset alfa
INSERT INTO
    storage.buckets (id, name, public)
VALUES (
        'alfa_assets',
        'alfa_assets',
        true
    )
ON CONFLICT (id) DO NOTHING;

-- ==========================================
-- 4. SECURITY: Row Level Security (RLS)
-- ==========================================

ALTER TABLE public.bravo ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.alfa ENABLE ROW LEVEL SECURITY;

-- Policy Bravo
CREATE POLICY "Allow read access to all users" ON public.bravo FOR
SELECT TO public USING (true);

CREATE POLICY "Allow insert access to authenticated users" ON public.bravo FOR INSERT TO authenticated
WITH
    CHECK (auth.uid () = user_id);

CREATE POLICY "Allow update and delete access to owner only" ON public.bravo FOR ALL TO authenticated USING (auth.uid () = user_id);

-- Policy Alfa (Berbasis kepemilikan di tabel Bravo)
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

-- ==========================================
-- 5. STORAGE POLICIES: Keamanan File
-- ==========================================

-- Publik bisa melihat gambar
CREATE POLICY "Allow public read access to alfa_assets" ON storage.objects FOR
SELECT TO public USING (bucket_id = 'alfa_assets');

-- User terautentikasi bisa upload
CREATE POLICY "Allow authenticated users to upload to alfa_assets" ON storage.objects FOR INSERT TO authenticated
WITH
    CHECK (bucket_id = 'alfa_assets');

-- User terautentikasi bisa update (upsert)
CREATE POLICY "Allow authenticated users to update alfa_assets" ON storage.objects
FOR UPDATE
    TO authenticated USING (bucket_id = 'alfa_assets');

-- Service Role (Admin/Edge Function) bypass aturan
CREATE POLICY "Service Role Bypass" ON storage.objects FOR ALL TO service_role USING (bucket_id = 'alfa_assets');

-- Policy Delete: Hanya pemilik data alfa yang bisa hapus file terkait
CREATE POLICY "Allow users to delete their own alfa_assets" ON storage.objects FOR DELETE TO authenticated USING (
    bucket_id = 'alfa_assets'
    AND EXISTS (
        SELECT 1
        FROM public.alfa a
            JOIN public.bravo b ON a.bravo_id = b.id
        WHERE
            b.user_id = auth.uid ()
            AND a.image_url = storage.objects.name -- Perbandingan '=' jauh lebih cepat dari 'LIKE'
    )
);

-- ==========================================
-- 6. CONFIGURATION & LOGGING
-- ==========================================

-- Menyimpan URL Edge Function ke setting database agar dinamis
ALTER DATABASE postgres
SET
    "app.settings.edge_function_url" TO 'https://kjntldyruleluffmmhkz.supabase.co/functions/v1/delete-storage-object';

-- Tabel Log untuk memantau proses penghapusan di Storage
CREATE TABLE IF NOT EXISTS public.storage_deletion_log (
    id uuid DEFAULT gen_random_uuid () PRIMARY KEY,
    file_path TEXT NOT NULL,
    status TEXT DEFAULT 'pending', -- 'pending', 'success', 'failed'
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ==========================================
-- 7. WEBHOOK TRIGGER: Auto-Delete Storage
-- ==========================================

-- Pastikan ekstensi http tersedia
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Fungsi untuk memanggil Edge Function saat data Alfa dihapus
CREATE OR REPLACE FUNCTION public.handle_delete_alfa_storage()
RETURNS TRIGGER 
SET search_path = public, net, vault -- Keamanan: Batasi akses skema
AS $$
DECLARE
  service_key text;
  ef_url text;
BEGIN
  -- 1. Ambil API Key admin dari Vault
  SELECT decrypted_secret INTO service_key 
  FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  -- 2. Ambil URL Edge Function dari setting
  ef_url := current_setting('app.settings.edge_function_url');

  -- 3. Catat ke log sebelum mencoba menghapus
  INSERT INTO public.storage_deletion_log (file_path, status)
  VALUES (OLD.image_url, 'pending');

  -- 4. Kirim sinyal ke Edge Function (Asinkron)
  PERFORM net.http_post(
    url := ef_url,
    body := jsonb_build_object(
        'old_record', OLD, 
        'type', 'DELETE'
    ),
    headers := jsonb_build_object(
        'Content-Type', 'application/json', 
        'Authorization', 'Bearer ' || service_key
    ),
    timeout_milliseconds := 2000
  );

  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: Jalankan fungsi di atas SETELAH baris alfa dihapus
CREATE
OR REPLACE TRIGGER on_alfa_deleted
AFTER DELETE ON public.alfa FOR EACH ROW
EXECUTE FUNCTION public.handle_delete_alfa_storage ()

-- ==========================================
-- 8. REALTIME: Aktifkan fitur Realtime
-- ==========================================
ALTER PUBLICATION supabase_realtime ADD TABLE public.bravo, public.alfa;