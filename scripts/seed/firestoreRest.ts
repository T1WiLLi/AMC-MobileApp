// Client REST minimal pour les scripts de seed d'organisme (T-194) : émulateur ou projet réel, mêmes appels.
// Pas de clé de service : en cloud, jeton OAuth de la session `firebase login` (comme seedFirestore.ts).
import { execFileSync } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'

export type Token = () => Promise<string>
export type RestValue = Record<string, unknown>
export type RestFields = Record<string, RestValue>
export type RestWrite = {
  update: { name: string, fields: RestFields }
  updateMask?: { fieldPaths: string[] }
  updateTransforms?: { fieldPath: string, appendMissingElements: { values: RestValue[] } }[]
  currentDocument?: { exists: boolean }
}

/** Valeur JS → Value de l'API REST Firestore (les `Date` deviennent des timestamps). */
export function toRestValue(value: unknown): RestValue {
  if (value === null || value === undefined) return { nullValue: null }
  if (value instanceof Date) return { timestampValue: value.toISOString() }
  if (typeof value === 'boolean') return { booleanValue: value }
  if (typeof value === 'number') return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value }
  if (typeof value === 'string') return { stringValue: value }
  if (Array.isArray(value)) return { arrayValue: { values: value.map(toRestValue) } }
  if (typeof value === 'object') return { mapValue: { fields: toRestFields(value as Record<string, unknown>) } }
  throw new Error(`Type non pris en charge : ${typeof value}`)
}

export function toRestFields(data: Record<string, unknown>): RestFields {
  return Object.fromEntries(Object.entries(data).map(([key, value]) => [key, toRestValue(value)]))
}

function firebaseCliToken(): Token {
  const configPath = join(homedir(), '.config', 'configstore', 'firebase-tools.json')
  let cached: { token: string, expiresAt: number } | null = null
  return async () => {
    if (!cached || cached.expiresAt - Date.now() < 120_000) {
      execFileSync('npx', ['-y', 'firebase-tools@latest', 'projects:list', '--json'], { stdio: 'ignore' })
      const tokens = JSON.parse(await readFile(configPath, 'utf8')).tokens ?? {}
      if (typeof tokens.access_token !== 'string') throw new Error('Pas de session Firebase : lancez `npx -y firebase-tools@latest login`.')
      cached = { token: tokens.access_token, expiresAt: Number(tokens.expires_at) || Date.now() + 1_800_000 }
    }
    return cached.token
  }
}

export type Client = ReturnType<typeof connect>

const loopback = /^(127\.0\.0\.1|localhost):[0-9]{1,5}$/

/** Se connecte à l'émulateur (hôtes locaux seulement) ou au projet réel. */
export function connect(target: string, projectId: string) {
  if (!/^[a-z0-9][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId)) throw new Error('Identifiant de projet invalide')
  let base: string
  let authBase: string
  let token: Token
  if (target === 'emulator') {
    const host = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080'
    const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099'
    if (!loopback.test(host)) throw new Error('FIRESTORE_EMULATOR_HOST doit être local')
    if (!loopback.test(authHost)) throw new Error('FIREBASE_AUTH_EMULATOR_HOST doit être local')
    base = `http://${host}`
    authBase = `http://${authHost}/identitytoolkit.googleapis.com`
    token = async () => 'owner'
  } else if (target === 'cloud') {
    base = 'https://firestore.googleapis.com'
    authBase = 'https://identitytoolkit.googleapis.com'
    token = firebaseCliToken()
  } else {
    throw new Error('--target emulator|cloud')
  }
  const database = `projects/${projectId}/databases/(default)`

  async function call(url: string, init: { method: string, body?: unknown }) {
    const response = await fetch(url, {
      method: init.method,
      headers: { Authorization: `Bearer ${await token()}`, 'Content-Type': 'application/json', 'x-goog-user-project': projectId },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
      redirect: 'error',
      signal: AbortSignal.timeout(60_000)
    })
    if (response.status === 404 && init.method === 'GET') return null
    if (!response.ok) throw new Error(`Appel REST échoué (HTTP ${response.status}) : ${(await response.text()).slice(0, 500)}`)
    return response.json() as Promise<unknown>
  }

  return {
    label: target === 'emulator' ? `émulateur ${base}, projet ${projectId}` : `projet Firebase RÉEL ${projectId}`,
    database,
    docName: (path: string) => `${database}/documents/${path}`,
    /** Champs REST d'un document, ou null s'il n'existe pas. */
    async getFields(path: string): Promise<RestFields | null> {
      const document = await call(`${base}/v1/${database}/documents/${path}`, { method: 'GET' }) as { fields?: RestFields } | null
      return document === null ? null : (document.fields ?? {})
    },
    async commit(writes: RestWrite[]) {
      for (let start = 0; start < writes.length; start += 400) {
        await call(`${base}/v1/${database}/documents:commit`, { method: 'POST', body: { writes: writes.slice(start, start + 400) } })
      }
    },
    /** uid Auth d'un courriel, ou null. */
    async uidForEmail(email: string): Promise<string | null> {
      const result = await call(`${authBase}/v1/projects/${projectId}/accounts:lookup`, {
        method: 'POST', body: { email: [email] }
      }) as { users?: { localId: string }[] } | null
      return result?.users?.[0]?.localId ?? null
    }
  }
}
