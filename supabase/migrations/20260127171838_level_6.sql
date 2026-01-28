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
-- 2. SCHEMAS & EXTENSIONS
-- ==========================================
-- Membuat skema khusus agar ekstensi tidak mengotori skema 'public'
CREATE SCHEMA IF NOT EXISTS extensions;

-- 1. Hapus ekstensi jika ada di tempat lama (CASCADE agar fungsi yang memakainya ikut terhapus sementara)
DROP EXTENSION IF EXISTS pg_net CASCADE;

DROP EXTENSION IF EXISTS pgcrypto CASCADE;

-- 2. Pasang ulang langsung ke skema extensions
-- Install/Pindahkan ekstensi ke skema extensions
-- pgcrypto biasanya digunakan untuk gen_random_uuid()
CREATE EXTENSION pg_net WITH SCHEMA extensions;
-- pg_net untuk HTTP request (Edge Functions)
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;

-- 3. Berikan izin akses agar skema extensions bisa dibaca
GRANT USAGE ON SCHEMA extensions TO postgres,
authenticated,
anon,
service_role;

-- Aktifkan pg_cron di skema extensions
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- Berikan izin agar superuser bisa mengelola cron
GRANT USAGE ON SCHEMA cron TO postgres;

-- ==========================================
-- 3. TABLES: Bravo (Parent) & Alfa (Child)
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
-- 4. STORAGE: Bucket Setup
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
-- 5. SECURITY: Row Level Security (RLS)
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
-- 6. STORAGE POLICIES: Keamanan File
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
-- 7. CONFIGURATION & LOGGING
-- ==========================================

-- Buat tabel khusus untuk menyimpan setting aplikasi
CREATE TABLE IF NOT EXISTS public.app_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Masukkan URL Edge Function ke tabel
INSERT INTO
    public.app_config (key, value)
VALUES (
        'edge_function_url',
        'https://kjntldyruleluffmmhkz.supabase.co/functions/v1/delete-storage-object'
    )
ON CONFLICT (key) DO
UPDATE
SET
    value = EXCLUDED.value;

CREATE TABLE IF NOT EXISTS public.storage_deletion_log (
    id uuid DEFAULT extensions.gen_random_uuid () PRIMARY KEY,
    file_path TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ==========================================
-- 8. WEBHOOK TRIGGER: Auto-Delete Storage
-- ==========================================

-- Fungsi untuk memanggil Edge Function saat data Alfa dihapus
CREATE OR REPLACE FUNCTION public.handle_delete_alfa_storage()
RETURNS TRIGGER 
SET search_path = public, extensions, net, vault
AS $$
DECLARE
  ef_url text;
BEGIN
  -- 1. Ambil URL dari tabel app_config
  SELECT value INTO ef_url FROM public.app_config WHERE key = 'edge_function_url';

  -- 2. Catat ke log seperti biasa
  INSERT INTO public.storage_deletion_log (file_path, status)
  VALUES (OLD.image_url, 'pending');

  -- 3. Kirim sinyal dengan Header Kustom
  PERFORM net.http_post(
    url := ef_url,
    body := jsonb_build_object(
        'old_record', OLD, 
        'type', 'DELETE'
    ),
    headers := jsonb_build_object(
        'Content-Type', 'application/json',
        -- Kita pakai header kustom di sini
        'x-custom-key', 'pasti-aman-banget-123' 
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
EXECUTE FUNCTION public.handle_delete_alfa_storage ();

-- ==========================================
-- 9. REALTIME: Aktifkan fitur Realtime
-- ==========================================
ALTER PUBLICATION supabase_realtime
ADD TABLE public.bravo,
public.alfa;

-- ==========================================
-- 10. KEAMANAN TAMBAHAN: LOCKDOWN CONFIG & LOGS
-- ==========================================

-- 1. Aktifkan RLS
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.storage_deletion_log ENABLE ROW LEVEL SECURITY;

-- 2. Kebijakan untuk app_config: Hanya Service Role (Admin) yang bisa akses
-- User anonim atau authenticated tidak bisa LIHAT maupun EDIT.
CREATE POLICY "Service Role Only" ON public.app_config FOR ALL TO service_role USING (true);

-- 3. Kebijakan untuk storage_deletion_log: Hanya Service Role (Admin) yang bisa akses
CREATE POLICY "Service Role Only" ON public.storage_deletion_log FOR ALL TO service_role USING (true);

-- ==========================================
-- 11. CRON JOB: Pembersihan Log Otomatis
-- ==========================================

CREATE OR REPLACE FUNCTION public.cleanup_old_storage_logs()
RETURNS void 
SET search_path = public
AS $$
BEGIN
  -- Mode Test: Hapus log yang sudah sukses/failed dan usianya > 10 detik
  DELETE FROM public.storage_deletion_log
  WHERE created_at < NOW() - INTERVAL '7 days'
  AND status IN ('success', 'failed');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Jadwalkan dengan aman (Gunakan blok DO agar tidak error di run pertama)
DO $$
BEGIN
    -- Coba hapus jadwal lama jika ada
    PERFORM cron.unschedule('daily-log-cleanup');
EXCEPTION WHEN OTHERS THEN
    -- Jika gagal (karena belum ada), abaikan saja dan lanjut
    NULL; 
END $$;

-- Daftarkan ulang dengan jadwal 1 menit
SELECT cron.schedule (
        'daily-log-cleanup', '0 0 * * *', 'SELECT public.cleanup_old_storage_logs()'
    );