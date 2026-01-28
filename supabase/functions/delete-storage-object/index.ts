// ==========================================
// 1. SETUP & IMPORTS
// ==========================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

interface DeletePayload {
  old_record: {
    image_url: string;
  };
  type: string;
}

Deno.serve(async (req) => {
  // ==========================================
  // 2. SECURITY & METHOD CHECK
  // ==========================================
  const customKey = req.headers.get("x-custom-key");
  const validKey = Deno.env.get("APP_DELETE_SECRET");

  // Validasi keamanan: Pastikan secret terpasang dan cocok
  if (!validKey || customKey !== validKey) {
    console.error("❌ Akses Ilegal atau Secret belum dikonfigurasi!");
    return new Response(JSON.stringify({ error: "Unauthorized" }), { 
      status: 401, 
      headers: { "Content-Type": "application/json" } 
    });
  }
  
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { 
      status: 405, 
      headers: { "Content-Type": "application/json" } 
    })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  // Variabel penampung di luar scope try agar bisa diakses di catch
  let rawPath: string | undefined;

  try {
    // ==========================================
    // 3. PAYLOAD PROCESSING
    // ==========================================
    const payload: DeletePayload = await req.json();
    rawPath = payload.old_record?.image_url;

    if (!rawPath) {
      return new Response(JSON.stringify({ message: "No image_url found, skipping" }), { status: 200 })
    }

    const fileName = rawPath.split('/').pop() as string;
    console.log(`🚀 Memproses penghapusan: ${fileName}`);

    // ==========================================
    // 4. STORAGE DELETION
    // ==========================================
    const { data: storageData, error: storageError } = await supabase.storage
      .from('alfa_assets')
      .remove([fileName]);

    if (storageError) throw storageError;

    // ==========================================
    // 5. UPDATE LOG STATUS (SUCCESS)
    // ==========================================
    await supabase
      .from('storage_deletion_log')
      .update({ status: 'success' })
      .eq('file_path', rawPath)
      .eq('status', 'pending');

    console.log(`✅ File ${fileName} terhapus & log diperbarui.`);

    return new Response(JSON.stringify({ message: "Success", storage: storageData }), { 
      headers: { "Content-Type": "application/json" },
      status: 200 
    });

  } catch (err) {
    // ==========================================
    // 6. ERROR HANDLING
    // ==========================================
    const errorMessage = err instanceof Error ? err.message : "Unknown error";
    console.error("❌ Critical Error:", errorMessage);

    // Gunakan rawPath yang sudah kita tangkap di awal blok try
    if (rawPath) {
      await supabase
        .from('storage_deletion_log')
        .update({ 
          status: 'failed', 
          error_message: errorMessage 
        })
        .eq('file_path', rawPath)
        .eq('status', 'pending');
    }

    return new Response(JSON.stringify({ error: errorMessage }), { 
      status: 400,
      headers: { "Content-Type": "application/json" }
    });
  }
});