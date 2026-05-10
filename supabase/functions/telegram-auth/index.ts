const DEFAULT_ALLOWED_ORIGINS = ['https://moonishe.github.io']
const LOCAL_ORIGIN_PATTERN = /^https?:\/\/(?:localhost|127\.0\.0\.1|\[::1\])(?::\d+)?$/i
const CORS_BASE_HEADERS = {
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Vary': 'Origin',
}

const REQUIRED_TELEGRAM_FIELDS = ['id', 'auth_date', 'hash'] as const
const TELEGRAM_AUTH_MAX_AGE_SECONDS = 86400
const TELEGRAM_AUTH_FUTURE_SKEW_SECONDS = 300
const RATE_LIMIT_WINDOW_SECONDS = 300
const RATE_LIMITS = {
  ip: 30,
  telegram: 12,
  invite: 20,
} as const

function getRequiredEnv(name: string): string {
  const value = Deno.env.get(name)
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`)
  }
  return value
}

async function hmacSha256(key: string, message: string): Promise<string> {
  const keyBuffer = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(key))
  const cryptoKey = await crypto.subtle.importKey(
    'raw', keyBuffer, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  )
  const sig = await crypto.subtle.sign('HMAC', cryptoKey, new TextEncoder().encode(message))
  return Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('')
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, '0')).join('')
}

function getClientIp(req: Request): string {
  return req.headers.get('cf-connecting-ip') || req.headers.get('x-real-ip') || 'unknown'
}

function normalizeTelegramAuthData(raw: unknown): Record<string, string> | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null

  const authData: Record<string, string> = {}
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (value === null || value === undefined) continue
    if (typeof value !== 'string' && typeof value !== 'number') return null
    authData[key] = String(value)
  }

  for (const field of REQUIRED_TELEGRAM_FIELDS) {
    if (!authData[field]) return null
  }

  return authData
}

function timingSafeEqualHex(left: string, right: string): boolean {
  if (left.length !== right.length || left.length % 2 !== 0) return false

  let diff = 0
  for (let i = 0; i < left.length; i += 2) {
    const leftByte = Number.parseInt(left.slice(i, i + 2), 16)
    const rightByte = Number.parseInt(right.slice(i, i + 2), 16)
    if (!Number.isFinite(leftByte) || !Number.isFinite(rightByte)) return false
    diff |= leftByte ^ rightByte
  }

  return diff === 0
}

async function verifyTelegramHash(authData: Record<string, string>): Promise<boolean> {
  const hash = authData.hash
  const data = { ...authData }
  delete data.hash
  const checkString = Object.keys(data).sort().map(k => `${k}=${data[k]}`).join('\n')
  const computedHash = await hmacSha256(getRequiredEnv('TELEGRAM_BOT_TOKEN'), checkString)
  return timingSafeEqualHex(computedHash, hash)
}

function generatePassword(): string {
  return crypto.randomUUID().replace(/-/g, '').slice(0, 32)
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

function sanitizeTelegramPhotoUrl(value: string | undefined): string | null {
  if (!value) return null

  if (value.startsWith('/')) {
    return value.startsWith('/i/userpic/') ? value : null
  }

  try {
    const url = new URL(value)
    const hostname = url.hostname.toLowerCase()
    if (url.protocol !== 'https:') return null
    if (hostname === 't.me' || hostname.endsWith('.t.me') || hostname === 'telegram.org' || hostname.endsWith('.telegram.org')) {
      return url.toString()
    }
  } catch (_) {
    return null
  }

  return null
}

async function checkRateLimit(
  adminClient: any,
  scope: keyof typeof RATE_LIMITS,
  value: string | null,
): Promise<boolean> {
  if (!value) return true

  const identifier = `${scope}:${await sha256Hex(value)}`
  const { data, error } = await adminClient.rpc('check_telegram_auth_rate_limit', {
    p_identifier: identifier,
    p_max_attempts: RATE_LIMITS[scope],
    p_window_seconds: RATE_LIMIT_WINDOW_SECONDS,
  })

  if (error) {
    console.error('telegram-auth rate limit check failed', error)
    return false
  }

  return data === true
}

async function findAuthUserIdByEmail(adminClient: any, email: string): Promise<string | null> {
  const { data, error } = await adminClient.rpc('get_auth_user_id_by_email', { p_email: email })

  if (error) {
    console.error('telegram-auth auth user lookup failed', error)
    return null
  }

  return typeof data === 'string' && data ? data : null
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
    const { auth_data, invite_code, turnstile_token } = await req.json()
    const authData = normalizeTelegramAuthData(auth_data)

    if (!authData) {
      return jsonResponse({ error: 'Missing auth data' }, 400)
    }

    if (turnstile_token && typeof turnstile_token === 'string') {
      const turnstileSecret = Deno.env.get('TURNSTILE_SECRET_KEY')
      if (turnstileSecret) {
        const formData = new URLSearchParams()
        formData.set('secret', turnstileSecret)
        formData.set('response', turnstile_token)
        const cfRes = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
          method: 'POST',
          body: formData,
        })
        const cfData = await cfRes.json()
        if (!cfData.success) {
          return jsonResponse({ error: 'Captcha verification failed' }, 400)
        }
      }
    }

    const authDate = Number(authData.auth_date)
    if (!Number.isFinite(authDate)) {
      return jsonResponse({ error: 'Invalid Telegram authentication' }, 401)
    }

    const now = Math.floor(Date.now() / 1000)
    if (authDate <= 0 || authDate > now + TELEGRAM_AUTH_FUTURE_SKEW_SECONDS || now - authDate > TELEGRAM_AUTH_MAX_AGE_SECONDS) {
      return jsonResponse({ error: 'Invalid Telegram authentication' }, 401)
    }

    const telegramId = authData.id
    const email = `telegram_${telegramId}@neurobench.local`

    const supabaseUrl = getRequiredEnv('SUPABASE_URL')
    const serviceRoleKey = getRequiredEnv('SUPABASE_SERVICE_ROLE_KEY')
    const anonKey = getRequiredEnv('SUPABASE_ANON_KEY')

    const { createClient } = await import('https://esm.sh/@supabase/supabase-js@2.49.4')
    const adminClient = createClient(supabaseUrl, serviceRoleKey)
    const anonClient = createClient(supabaseUrl, anonKey)

    const inviteCodeForLimit = typeof invite_code === 'string' ? invite_code.trim().toUpperCase() : null
    const rateLimitOk = await Promise.all([
      checkRateLimit(adminClient, 'ip', getClientIp(req)),
      checkRateLimit(adminClient, 'telegram', telegramId),
      checkRateLimit(adminClient, 'invite', inviteCodeForLimit),
    ])

    if (!rateLimitOk.every(Boolean)) {
      return jsonResponse({ error: 'Too many requests' }, 429)
    }

    if (!await verifyTelegramHash(authData)) {
      return jsonResponse({ error: 'Invalid Telegram authentication' }, 401)
    }

    const password = generatePassword()

    const tgProfile = {
      telegram_username: authData.username || null,
      telegram_first_name: authData.first_name || null,
      telegram_last_name: authData.last_name || null,
      telegram_photo_url: sanitizeTelegramPhotoUrl(authData.photo_url),
    }

    let existingUserId: string | null = null
    let pendingAuthUserId: string | null = null
    let pendingProfileExists = false

    const { data: byTgId } = await adminClient
      .from('profiles')
      .select('user_id, is_verified, used_invite_code_id')
      .eq('telegram_id', telegramId)
      .maybeSingle()

    if (byTgId) {
      if (byTgId.is_verified || byTgId.used_invite_code_id) {
        existingUserId = byTgId.user_id
      } else {
        pendingAuthUserId = byTgId.user_id
        pendingProfileExists = true
      }
    }

    if (!existingUserId && !pendingAuthUserId) {
      const { data: byEmail } = await adminClient
        .from('profiles')
        .select('user_id, telegram_id, is_verified, used_invite_code_id')
        .eq('email', email)
        .maybeSingle()

      if (byEmail) {
        if (byEmail.is_verified || byEmail.used_invite_code_id) {
          existingUserId = byEmail.user_id
          if (!byEmail.telegram_id) {
            await adminClient
              .from('profiles')
              .update({ telegram_id: telegramId, ...tgProfile })
              .eq('user_id', existingUserId)
          }
        } else {
          pendingAuthUserId = byEmail.user_id
          pendingProfileExists = true
        }
      }
    }

    if (!existingUserId && !pendingAuthUserId) {
      pendingAuthUserId = await findAuthUserIdByEmail(adminClient, email)
    }

    if (existingUserId) {
      const { data: sessionData, error: sessionError } = await anonClient.auth.signInWithPassword({ email, password })

      if (sessionError) {
        await adminClient.auth.admin.updateUserById(existingUserId, { password })
        const retry = await anonClient.auth.signInWithPassword({ email, password })
        if (retry.error) {
          console.error('telegram-auth session retry failed', retry.error)
          return jsonResponse({ error: 'Internal server error' }, 500)
        }
        await adminClient
          .from('profiles')
          .update({ telegram_id: telegramId, ...tgProfile })
          .eq('user_id', existingUserId)
        return jsonResponse({
          access_token: retry.data.session.access_token,
          refresh_token: retry.data.session.refresh_token,
          is_new: false
        })
      }

      await adminClient
        .from('profiles')
        .update({ telegram_id: telegramId, ...tgProfile })
        .eq('user_id', existingUserId)

      return jsonResponse({
        access_token: sessionData.session.access_token,
        refresh_token: sessionData.session.refresh_token,
        is_new: false
      })
    }

    if (!invite_code || typeof invite_code !== 'string') {
      return jsonResponse({ error: 'Для регистрации нужен инвайт-код', needs_invite: true }, 400)
    }

    const inviteCodeUpper = invite_code.trim().toUpperCase()
    if (!inviteCodeUpper) {
      return jsonResponse({ error: 'Invite code is required', needs_invite: true }, 400)
    }

    const { data: validCode } = await adminClient
      .from('invite_codes')
      .select('id, max_uses, use_count, expires_at')
      .eq('code', inviteCodeUpper)
      .maybeSingle()

    const codeExpired = validCode?.expires_at && new Date(validCode.expires_at).getTime() <= Date.now()
    const codeExhausted = validCode && validCode.max_uses !== null && validCode.use_count >= validCode.max_uses
    if (!validCode || codeExpired || codeExhausted) {
      return jsonResponse({ error: 'Инвайт-код недействителен или уже использован' }, 400)
    }

    let targetUserId = pendingAuthUserId
    let createdAuthUser = false

    if (targetUserId) {
      const { error: updateAuthError } = await adminClient.auth.admin.updateUserById(targetUserId, {
        password,
        user_metadata: {
          invite_code: inviteCodeUpper,
          telegram_id: telegramId
        }
      })

      if (updateAuthError) {
        console.error('telegram-auth pending auth user update failed', updateAuthError)
        return jsonResponse({ error: 'Internal server error' }, 500)
      }
    } else {
      const { data: newUser, error: createError } = await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          invite_code: inviteCodeUpper,
          telegram_id: telegramId
        }
      })

      if (createError || !newUser) {
        console.error('telegram-auth create user failed', createError)
        return jsonResponse({ error: 'Internal server error' }, 500)
      }

      targetUserId = newUser.id
      createdAuthUser = true
    }

    if (!targetUserId) {
      console.error('telegram-auth missing target user id')
      return jsonResponse({ error: 'Internal server error' }, 500)
    }

    const { error: pendingProfileError } = await adminClient
      .from('profiles')
      .upsert({
        user_id: targetUserId,
        email,
        is_verified: false,
        pending_invite_code: inviteCodeUpper,
      }, { onConflict: 'user_id' })

    if (pendingProfileError) {
      console.error('telegram-auth pending profile upsert failed', pendingProfileError)
      if (createdAuthUser && targetUserId) {
        const { error: cleanupUserError } = await adminClient.auth.admin.deleteUser(targetUserId)
        if (cleanupUserError) console.error('telegram-auth auth user cleanup failed', cleanupUserError)
      }
      return jsonResponse({ error: 'Internal server error' }, 500)
    }

    const { data: inviteId, error: claimError } = await adminClient
      .rpc('admin_claim_invite_for_user', { p_code: inviteCodeUpper, p_user_id: targetUserId })

    if (claimError || !inviteId) {
      if (claimError) console.error('telegram-auth invite claim failed', claimError)
      if (pendingProfileExists) {
        const { error: cleanupProfileError } = await adminClient
          .from('profiles')
          .update({ is_verified: false, pending_invite_code: null })
          .eq('user_id', targetUserId)
        if (cleanupProfileError) console.error('telegram-auth profile cleanup failed', cleanupProfileError)
      } else {
        const { error: cleanupProfileError } = await adminClient
          .from('profiles')
          .delete()
          .eq('user_id', targetUserId)
        if (cleanupProfileError) console.error('telegram-auth profile cleanup failed', cleanupProfileError)
      }
      if (createdAuthUser && targetUserId) {
        const { error: cleanupUserError } = await adminClient.auth.admin.deleteUser(targetUserId)
        if (cleanupUserError) console.error('telegram-auth auth user cleanup failed', cleanupUserError)
      }
      return jsonResponse({ error: 'Инвайт-код недействителен или уже использован' }, 400)
    }

    await adminClient
      .from('profiles')
      .upsert({
        user_id: targetUserId,
        email,
        is_verified: false,
        telegram_id: telegramId,
        ...tgProfile,
        used_invite_code_id: inviteId,
        pending_invite_code: null,
      }, { onConflict: 'user_id' })

    const { data: sessionData, error: sessionError } = await anonClient.auth.signInWithPassword({ email, password })

    if (sessionError || !sessionData) {
      console.error('telegram-auth initial session creation failed', sessionError)
      return jsonResponse({ error: 'Internal server error' }, 500)
    }

    return jsonResponse({
      access_token: sessionData.session.access_token,
      refresh_token: sessionData.session.refresh_token,
      is_new: true
    })

  } catch (err) {
    console.error('telegram-auth fatal error', err)
    return jsonResponse({ error: 'Internal server error' }, 500)
  }
})
