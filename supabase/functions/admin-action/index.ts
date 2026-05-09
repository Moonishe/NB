const DEFAULT_ALLOWED_ORIGINS = ['https://moonishe.github.io']
const LOCAL_ORIGIN_PATTERN = /^https?:\/\/(?:localhost|127\.0\.0\.1|\[::1\])(?::\d+)?$/i
const CORS_BASE_HEADERS = {
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Vary': 'Origin',
}

function getRequiredEnv(name: string): string {
  const value = Deno.env.get(name)
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`)
  }
  return value
}

function getAllowedOrigins(): Set<string> {
  const configured = (Deno.env.get('ALLOWED_ORIGINS') || '')
    .split(',')
    .map(origin => origin.trim())
    .filter(Boolean)

  return new Set([...DEFAULT_ALLOWED_ORIGINS, ...configured])
}

function getCorsHeaders(req: Request): Record<string, string> | null {
  const origin = req.headers.get('Origin')
  if (!origin) return { ...CORS_BASE_HEADERS }

  if (getAllowedOrigins().has(origin) || LOCAL_ORIGIN_PATTERN.test(origin)) {
    return { ...CORS_BASE_HEADERS, 'Access-Control-Allow-Origin': origin }
  }

  return null
}

function makeJsonResponse(corsHeaders: Record<string, string>) {
  return (body: Record<string, unknown>, status = 200): Response => {
    return new Response(JSON.stringify(body), {
      status,
      headers: { 'Content-Type': 'application/json', ...corsHeaders }
    })
  }
}

Deno.serve(async (req: Request) => {
  const corsHeaders = getCorsHeaders(req)
  const jsonResponse = makeJsonResponse(corsHeaders || { ...CORS_BASE_HEADERS })

  if (!corsHeaders) {
    if (req.method === 'OPTIONS') {
      return new Response(null, { status: 403, headers: CORS_BASE_HEADERS })
    }
    return jsonResponse({ error: 'Forbidden origin' }, 403)
  }

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return jsonResponse({ error: 'Unauthorized' }, 401)
    }

    const supabaseUrl = getRequiredEnv('SUPABASE_URL')
    const serviceRoleKey = getRequiredEnv('SUPABASE_SERVICE_ROLE_KEY')

    const { createClient } = await import('https://esm.sh/@supabase/supabase-js@2.49.4')
    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    const token = authHeader.replace('Bearer ', '')
    const { data: userData, error: userError } = await adminClient.auth.getUser(token)
    if (userError || !userData.user) {
      console.error('admin-action token validation failed', userError ?? 'No user returned')
      return jsonResponse({ error: 'Unauthorized' }, 401)
    }

    const adminId = userData.user.id
    const { data: adminCheck } = await adminClient
      .from('admin_users')
      .select('id')
      .eq('user_id', adminId)
      .maybeSingle()

    if (!adminCheck) {
      return jsonResponse({ error: 'Not an admin' }, 403)
    }

    const { action, user_id } = await req.json()

    if (!action || !user_id) {
      return jsonResponse({ error: 'Missing action or user_id' }, 400)
    }

    if (action === 'delete_user') {
      if (user_id === adminId) {
        return jsonResponse({ error: 'Cannot delete yourself' }, 400)
      }

      const { data: targetIsAdmin } = await adminClient
        .from('admin_users')
        .select('id')
        .eq('user_id', user_id)
        .maybeSingle()

      if (targetIsAdmin) {
        return jsonResponse({ error: 'Cannot delete another admin' }, 400)
      }

      const { data: profile } = await adminClient
        .from('profiles')
        .select('user_id')
        .eq('user_id', user_id)
        .maybeSingle()

      if (!profile) {
        return jsonResponse({ error: 'User not found' }, 404)
      }

      const { error: deleteError } = await adminClient.auth.admin.deleteUser(user_id)
      if (deleteError) {
        console.error('admin-action delete user failed', { user_id, error: deleteError })
        return jsonResponse({ error: 'Delete failed' }, 500)
      }

      const cleanupSteps = [
        {
          label: 'invite_code_uses.user_id',
          run: () => adminClient.from('invite_code_uses').delete().eq('user_id', user_id),
        },
        {
          label: 'invite_codes.created_by',
          run: () => adminClient.from('invite_codes').update({ created_by: null }).eq('created_by', user_id),
        },
        {
          label: 'invite_codes.used_by',
          run: () => adminClient.from('invite_codes').update({ used_by: null }).eq('used_by', user_id),
        },
        {
          label: 'forum_threads.last_post_by',
          run: () => adminClient.from('forum_threads').update({ last_post_by: null }).eq('last_post_by', user_id),
        },
      ]

      for (const step of cleanupSteps) {
        try {
          const { error } = await step.run()
          if (error) {
            console.error('admin-action post-delete cleanup failed', { user_id, step: step.label, error })
          }
        } catch (error) {
          console.error('admin-action post-delete cleanup threw', { user_id, step: step.label, error })
        }
      }

      await adminClient.from('admin_actions').insert({
        actor_id: adminId,
        action: 'delete_user',
        target_id: user_id,
        created_at: new Date().toISOString(),
      })

      return jsonResponse({ success: true })
    }

    return jsonResponse({ error: 'Unknown action' }, 400)

  } catch (err) {
    console.error('admin-action fatal error', err)
    return jsonResponse({ error: 'Internal server error' }, 500)
  }
})
