// Seed idempotent des données de démo dans Firestore, SANS rien supprimer (contrairement à seedDemo.ts).
// Écrit chaque document des fixtures à son id stable (set complet) et crée ou met à jour un compte Auth
// par utilisateur de users.json (uid = id du document, B-029) : relancer le script remet la démo dans son
// état initial sans toucher aux autres documents ni aux autres comptes Auth.
// Mot de passe des comptes : GRENIER_DEMO_PASSWORD, sinon généré et affiché une seule fois.
//
//   Émulateur (défaut) : npm --prefix scripts/seed run seed:firestore
//   Projet réel        : npm --prefix scripts/seed run seed:firestore -- --target cloud --yes
//
// Cloud : utilise la session de `firebase login` (jeton OAuth de la CLI Firebase), jamais de clé de service.
import { execFileSync } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { parseArgs } from 'node:util'
import { deleteApp, initializeApp, type Credential } from 'firebase-admin/app'
import { getFirestore, Timestamp, type DocumentData } from 'firebase-admin/firestore'
import { demoAccounts, demoPassword, millisecondsPerDay, passwordNotice, personaUserIds, readDemoSeed } from './catalog.ts'

type Write = { path: string, data: DocumentData }

const fixturesDirectory = new URL('./fixtures/', import.meta.url)

// Même plan de documents que seedDemo.ts (validé, sous-collections comprises), sans suppression.
async function buildWrites(seedDay: number) {
  const seed = await readDemoSeed(fixturesDirectory, seedDay)
  const counts: Record<string, number> = {}
  for (const { path } of seed.documents) {
    const collection = path.split('/').filter((_, index) => index % 2 === 0).join('/')
    counts[collection] = (counts[collection] ?? 0) + 1
  }
  return { writes: seed.documents as Write[], counts, accounts: demoAccounts(seed.users) }
}

type DemoAccount = ReturnType<typeof demoAccounts>[number]

// Comptes Auth de démo (B-029) par l'API REST Identity Toolkit, émulateur comme projet réel :
// crée les comptes manquants et remet à jour les autres (courriel, nom, mot de passe). Ne supprime rien.
async function syncAccounts(base: string, projectId: string, token: () => Promise<string>,
  accounts: DemoAccount[], password: string) {
  const call = async (method: string, body: unknown) => {
    const response = await fetch(`${base}/v1/projects/${projectId}/${method}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${await token()}`, 'Content-Type': 'application/json', 'x-goog-user-project': projectId },
      body: JSON.stringify(body),
      redirect: 'error',
      signal: AbortSignal.timeout(30_000)
    })
    if (!response.ok) throw new Error(`Auth ${method} échoué (HTTP ${response.status}) : ${(await response.text()).slice(0, 300)}`)
    return response.json() as Promise<{ users?: { localId: string }[] }>
  }
  const existing = new Set(((await call('accounts:lookup', { localId: accounts.map(({ uid }) => uid) })).users ?? [])
    .map(({ localId }) => localId))
  let created = 0
  for (const { uid, email, displayName } of accounts) {
    const fields = { localId: uid, email, displayName, password, emailVerified: true }
    if (existing.has(uid)) {
      await call('accounts:update', fields)
    } else {
      await call('accounts', fields)
      created += 1
    }
  }
  return { created, updated: accounts.length - created }
}

// Jeton OAuth de la session `firebase login` (rafraîchi par un appel à la CLI juste avant).
function firebaseCliCredential(): Credential {
  const configPath = join(homedir(), '.config', 'configstore', 'firebase-tools.json')
  let cached: { token: string, expiresAt: number } | null = null
  return {
    async getAccessToken() {
      if (!cached || cached.expiresAt - Date.now() < 120_000) {
        execFileSync('npx', ['-y', 'firebase-tools@latest', 'projects:list', '--json'], { stdio: 'ignore' })
        const tokens = JSON.parse(await readFile(configPath, 'utf8')).tokens ?? {}
        if (typeof tokens.access_token !== 'string') {
          throw new Error('Pas de session Firebase : lancez `npx -y firebase-tools@latest login`.')
        }
        cached = { token: tokens.access_token, expiresAt: Number(tokens.expires_at) || Date.now() + 1_800_000 }
      }
      return { access_token: cached.token, expires_in: Math.floor((cached.expiresAt - Date.now()) / 1000) }
    }
  }
}

// Valeur JS → Value de l'API REST Firestore.
function toRestValue(value: unknown): Record<string, unknown> {
  if (value === null || value === undefined) return { nullValue: null }
  if (value instanceof Timestamp) return { timestampValue: value.toDate().toISOString() }
  if (typeof value === 'boolean') return { booleanValue: value }
  if (typeof value === 'number') {
    return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value }
  }
  if (typeof value === 'string') return { stringValue: value }
  if (Array.isArray(value)) return { arrayValue: { values: value.map(toRestValue) } }
  if (typeof value === 'object') {
    return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, toRestValue(v)])) } }
  }
  throw new Error(`Type non pris en charge : ${typeof value}`)
}

async function commitWithRest(projectId: string, credential: Credential, writes: Write[]) {
  const database = `projects/${projectId}/databases/(default)`
  for (let start = 0; start < writes.length; start += 400) {
    const { access_token: token } = await credential.getAccessToken()
    const body = {
      writes: writes.slice(start, start + 400).map(({ path, data }) => ({
        update: { name: `${database}/documents/${path}`, fields: (toRestValue(data) as { mapValue: { fields: unknown } }).mapValue.fields }
      }))
    }
    const response = await fetch(`https://firestore.googleapis.com/v1/${database}/documents:commit`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', 'x-goog-user-project': projectId },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(60_000)
    })
    if (!response.ok) throw new Error(`commit REST échoué (HTTP ${response.status}) : ${(await response.text()).slice(0, 500)}`)
  }
}

async function seedFirestore() {
  const { values } = parseArgs({
    options: {
      target: { type: 'string', default: 'emulator' },
      project: { type: 'string', default: 'amc-2026-8ab03' },
      yes: { type: 'boolean', default: false },
      'dry-run': { type: 'boolean', default: false }
    }
  })
  const projectId = values.project
  if (!/^[a-z0-9][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId)) throw new Error('Identifiant de projet invalide')
  if (values.target !== 'emulator' && values.target !== 'cloud') throw new Error('--target emulator|cloud')

  const seedDay = Math.floor(Date.now() / millisecondsPerDay) * millisecondsPerDay
  const { writes, counts, accounts } = await buildWrites(seedDay)
  const summary = Object.entries(counts).map(([name, count]) => `${name}: ${count}`).join(', ')

  if (values['dry-run']) {
    console.log(`[dry-run] ${writes.length} documents : ${summary}`)
    console.log(`[dry-run] ${accounts.length} comptes Auth de démo`)
    return
  }
  const { password, generated } = demoPassword()
  function reportAccounts({ created, updated }: { created: number, updated: number }) {
    console.log(`Comptes Auth de démo : ${created} créés, ${updated} mis à jour. Personas :`)
    for (const account of accounts.filter(({ uid }) => (personaUserIds as readonly string[]).includes(uid))) {
      console.log(`  ${account.displayName} : ${account.email}`)
    }
    console.log(passwordNotice(generated, password))
  }

  let credential: Credential | undefined
  let authHost: string | undefined
  if (values.target === 'emulator') {
    const host = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080'
    if (!/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(host)) throw new Error('FIRESTORE_EMULATOR_HOST doit être local')
    process.env.FIRESTORE_EMULATOR_HOST = host
    authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099'
    if (!/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(authHost)) throw new Error('FIREBASE_AUTH_EMULATOR_HOST doit être local')
    console.log(`Cible : émulateur ${host} (Auth ${authHost}), projet ${projectId}`)
  } else {
    delete process.env.FIRESTORE_EMULATOR_HOST
    delete process.env.FIREBASE_AUTH_EMULATOR_HOST
    if (!values.yes) {
      throw new Error(`Écriture sur le VRAI projet ${projectId} : relancez avec --yes pour confirmer.`)
    }
    credential = firebaseCliCredential()
    console.log(`Cible : projet Firebase réel ${projectId}`)
  }
  process.env.METADATA_SERVER_DETECTION = 'none'

  if (credential) {
    // L'Admin SDK Firestore exige une clé de service ou l'ADC : en cloud, on passe par l'API REST.
    await commitWithRest(projectId, credential, writes)
    console.log(`Seed terminé : ${writes.length} documents (${summary}).`)
    const cloud = credential
    reportAccounts(await syncAccounts('https://identitytoolkit.googleapis.com', projectId,
      async () => (await cloud.getAccessToken()).access_token, accounts, password))
    return
  }

  const app = initializeApp({ projectId }, `seed-${Date.now()}`)
  const db = getFirestore(app)
  try {
    for (let start = 0; start < writes.length; start += 400) {
      const batch = db.batch()
      for (const { path, data } of writes.slice(start, start + 400)) batch.set(db.doc(path), data)
      await batch.commit()
    }
    console.log(`Seed terminé : ${writes.length} documents (${summary}).`)
    reportAccounts(await syncAccounts(`http://${authHost}/identitytoolkit.googleapis.com`, projectId,
      async () => 'owner', accounts, password))
  } finally {
    await db.terminate()
    await deleteApp(app)
  }
}

seedFirestore().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error)
  process.exitCode = 1
})
