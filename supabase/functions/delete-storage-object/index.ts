// ==========================================
// 1. SETUP & IMPORTS
// ==========================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// Definisi Interface untuk Payload agar kode lebih terstruktur
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
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { 
      status: 405, 
      headers: { "Content-Type": "application/json" } 
    })
  }

  // Inisialisasi Supabase Client dengan Service Role Key (Admin Privileges)
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  let payload: DeletePayload;
  let rawPath: string;

  try {
    // ==========================================
    // 3. PAYLOAD PROCESSING
    // ==========================================
    payload = await req.json()
    rawPath = payload.old_record?.image_url

    // Jika tidak ada nama file, kita anggap selesai (tidak ada yang perlu dihapus)
    if (!rawPath) {
      return new Response(JSON.stringify({ message: "No image_url found, skipping" }), { status: 200 })
    }

    // Ekstraksi nama file saja (antisipasi jika data di DB berisi path lengkap/URL)
    const fileName = rawPath.split('/').pop() as string;

    console.log(`Processing deletion for: ${fileName}`);

    // ==========================================
    // 4. STORAGE DELETION
    // ==========================================
    const { data: storageData, error: storageError } = await supabase.storage
      .from('alfa_assets')
      .remove([fileName])

    if (storageError) throw storageError

    // ==========================================
    // 5. UPDATE LOG STATUS (SUCCESS)
    // ==========================================
    // Mencari log terbaru untuk file ini yang masih 'pending'
    await supabase
      .from('storage_deletion_log')
      .update({ status: 'success' })
      .eq('file_path', rawPath)
      .eq('status', 'pending');

    console.log(`Successfully deleted ${fileName} and updated log.`);

    return new Response(JSON.stringify({ 
      message: "Deletion completed", 
      storage: storageData 
    }), { 
      headers: { "Content-Type": "application/json" },
      status: 200 
    })

  } catch (err) {
    // ==========================================
    // 6. ERROR HANDLING & FAILED LOG
    // ==========================================
    const errorMessage = err instanceof Error ? err.message : "Unknown error occured";
    console.error("Critical Error:", errorMessage);

    // Update log menjadi 'failed' agar kita bisa mendeteksi file sampah nantinya
    const payloadJson = await req.json().catch(() => ({}));
    const errorPath = payloadJson.old_record?.image_url;

    if (errorPath) {
      await supabase
        .from('storage_deletion_log')
        .update({ 
          status: 'failed', 
          error_message: errorMessage 
        })
        .eq('file_path', errorPath)
        .eq('status', 'pending');
    }

    return new Response(JSON.stringify({ error: errorMessage }), { 
      status: 400,
      headers: { "Content-Type": "application/json" }
    })
  }
})