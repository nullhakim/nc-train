import "dotenv/config";
import { createClient } from "@supabase/supabase-js";
import * as fs from "node:fs";
import * as path from "node:path";

const supabaseUrl = process.env.SUPABASE_URL!;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

// Initialize the client with service_role
// We add 'auth' configurations to ensure it acts as an administrative superuser
const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

const BUCKET_NAME = "alfa_assets";

async function seedStorage() {
  console.log("🧹 Cleaning up bucket before seeding...");
  
  // 1. List all files in the bucket
  const { data: files } = await supabase.storage.from(BUCKET_NAME).list();
  
  if (files && files.length > 0) {
    // 2. Delete them all
    const filesToRemove = files.map((x) => x.name);
    await supabase.storage.from(BUCKET_NAME).remove(filesToRemove);
    console.log("✅ Bucket cleared.");
  }
  
  console.log("🚀 Starting Storage Seed as Admin...");

  const filesToUpload = [
    { fileName: "john_doe.png", localPath: "./seed_images/john.png" },
    { fileName: "jane_smith.png", localPath: "./seed_images/jane.png" },
  ];

  for (const item of filesToUpload) {
    const filePath = path.resolve(item.localPath);
    if (!fs.existsSync(filePath)) {
      console.warn(`⚠️ File not found: ${item.localPath}`);
      continue;
    }

    const fileBuffer = fs.readFileSync(filePath);

    // Using the service_role key here BYPASSES RLS policies on storage.objects
    // provided we are hitting the API with the correct headers.
    const { data, error } = await supabase.storage
      .from(BUCKET_NAME)
      .upload(item.fileName, fileBuffer, {
        contentType: "image/png",
        upsert: true,
      });

    if (error) {
      console.error(`❌ Error uploading ${item.fileName}:`, error.message);

      // If it still fails, it's likely because the bucket itself has RLS
      // and service_role isn't explicitly allowed in the bucket's metadata.
    } else {
      console.log(`✅ Uploaded: ${item.fileName}`);
    }
  }
  console.log("🏁 Storage Seed Finished!");
}

seedStorage();
