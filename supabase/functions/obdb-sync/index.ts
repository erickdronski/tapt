// Retired one-shot importer (2026-07-09). The Open Brewery DB ingest ran to
// completion (8,666 staged / 8,145 breweries + 8,168 venues applied).
// Kept disabled; re-deploy from repo history if a re-sync is ever needed.
Deno.serve(() => new Response(JSON.stringify({ error: "retired" }), { status: 410, headers: { "content-type": "application/json" } }));
