# Vendored Browser Dependencies

These files replace runtime CDN script loads in production HTML pages.

- `tailwind/tailwindcss-3.4.17-cdn.js` from `https://cdn.tailwindcss.com/3.4.17`
- `supabase/supabase-js-2.49.4.min.js` from `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.49.4/dist/umd/supabase.min.js`
- `dompurify/purify-3.2.5.min.js` from `https://cdn.jsdelivr.net/npm/dompurify@3.2.5/dist/purify.min.js`

The HTML CSP still allows inline/eval because the current pages use inline
Tailwind config and the Tailwind browser runtime. Tightening that further
requires moving inline scripts to local files and replacing the Tailwind CDN
runtime with generated CSS.
