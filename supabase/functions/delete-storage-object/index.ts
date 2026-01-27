// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

Deno.serve(async (req) => {
try {
    const payload = await req.json()
    console.log("Payload received:", payload)

    const fileName = payload.old_record?.image_url

    if (!fileName) {
      return new Response("No filename provided", { status: 200 })
    }

    // Initialize the client inside the handler
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { data, error } = await supabase.storage
      .from('alfa_assets')
      .remove([fileName])

    if (error) throw error

    return new Response(JSON.stringify({ deleted: data }), { 
      headers: { "Content-Type": "application/json" },
      status: 200 
    })

  } catch (err) {
    return new Response(err.message, { status: 400 })
  }
})

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/delete-storage-object' \
    --header 'Authorization: Bearer eyJhbGciOiJFUzI1NiIsImtpZCI6ImI4MTI2OWYxLTIxZDgtNGYyZS1iNzE5LWMyMjQwYTg0MGQ5MCIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjIwODQ4OTM3NTN9.Q47JVgyvZOnuwZi-T9ltUd1EF6lpWS1msgh7mPr_bKPH3laXvI70LhsxhIFYUOw7eF34zY70P8Os8vn9i7NqiA' \
    --header 'Content-Type: application/json' \
    --data '{"name":"Functions"}'

*/
