import "dotenv/config";
import { createClient } from "@supabase/supabase-js";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

// Helper untuk menangani path folder agar aman di berbagai OS
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.error("❌ ERROR: SUPABASE_URL atau SERVICE_ROLE_KEY tidak ditemukan di .env");
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);
const BUCKET_NAME = "alfa_assets";

/**
 * Daftar file yang akan disemai (seeded)
 */
const FILES_TO_SEED = [
  { fileName: "john_doe.png", localPath: "./seed_images/john.png" },
  { fileName: "jane_smith.png", localPath: "./seed_images/jane.png" },
];

async function seedStorage() {
  console.log("🚀 Memulai proses Seed Storage...");

  // 1. Cek apakah Bucket ada
  const { data: bucket, error: bucketError } = await supabase.storage.getBucket(BUCKET_NAME);
  if (bucketError || !bucket) {
    console.error(`❌ Bucket '${BUCKET_NAME}' tidak ditemukan. Pastikan migrasi SQL sudah dijalankan.`);
    return;
  }

  // 2. Bersihkan hanya file yang akan kita seed (lebih aman daripada hapus semua)
  console.log("🧹 Membersihkan file lama yang bersangkutan...");
  const filesToRemove = FILES_TO_SEED.map(f => f.fileName);
  await supabase.storage.from(BUCKET_NAME).remove(filesToRemove);

  // 3. Upload File secara Paralel (lebih cepat menggunakan Promise.all)
  console.log("📤 Mengunggah file ke Supabase Storage...");
  
  const uploadPromises = FILES_TO_SEED.map(async (item) => {
    // Membuat path absolut agar tidak error meski dijalankan dari folder mana pun
    const absolutePath = path.resolve(__dirname, item.localPath);

    if (!fs.existsSync(absolutePath)) {
      return `⚠️ File lokal tidak ditemukan: ${item.localPath}`;
    }

    const fileBuffer = fs.readFileSync(absolutePath);

    const { error } = await supabase.storage
      .from(BUCKET_NAME)
      .upload(item.fileName, fileBuffer, {
        contentType: "image/png",
        upsert: true,
      });

    if (error) {
      return `❌ Gagal upload ${item.fileName}: ${error.message}`;
    } else {
      return `✅ Berhasil upload: ${item.fileName}`;
    }
  });

  // Jalankan semua proses upload secara bersamaan
  const results = await Promise.all(uploadPromises);
  results.forEach(res => console.log(res));

  console.log("🏁 Storage Seed Selesai!");
}

seedStorage();