// Seed idempotent des données de démo dans Firestore, SANS rien supprimer (contrairement à seedDemo.ts).
// Écrit chaque document des fixtures à son id stable (set complet) : relancer le script remet la démo
// dans son état initial sans toucher aux autres documents ni aux comptes Auth.
//
//   Émulateur (défaut) : npm --prefix scripts/seed run seed:firestore
//   Projet réel        : npm --prefix scripts/seed run seed:firestore -- --target cloud --yes
//
// Cloud : utilise la session de `firebase login` (jeton OAuth de la CLI Firebase), jamais de clé de service.
import { execFileSync } from 'node:child_process'
import { access, readFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { parseArgs } from 'node:util'
import { deleteApp, initializeApp, type Credential } from 'firebase-admin/app'
import { getFirestore, Timestamp, type DocumentData } from 'firebase-admin/firestore'
import { millisecondsPerDay, readCatalog } from './catalog.ts'

type Fixture = Record<string, unknown> & { id: string }
type Write = { path: string, data: DocumentData }

const fixturesDirectory = new URL('./fixtures/', import.meta.url)
const montrealZone = 'America/Montreal'

// Décalage (ms) entre l'heure de Montréal et UTC à un instant donné.
function montrealOffset(instant: number): number {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
    timeZone: montrealZone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit'
  }).formatToParts(instant).map(({ type, value }) => [type, Number(value)]))
  const asUTC = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second)
  return asUTC - instant
}

// Jour du seed + inDays, à l'heure locale de Montréal hh:mm.
function montrealTime(seedDay: number, inDays: number, hour: number, minute: number): Timestamp {
  const day = new Date(seedDay + inDays * millisecondsPerDay)
  const guess = Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), hour, minute)
  return Timestamp.fromMillis(guess - montrealOffset(guess))
}

function hhmm(value: unknown): [number, number] {
  const match = typeof value === 'string' ? /^([01][0-9]|2[0-3]):([0-5][0-9])$/.exec(value) : null
  if (!match) throw new Error(`Heure invalide : ${String(value)}`)
  return [Number(match[1]), Number(match[2])]
}

async function readOptional(filename: string): Promise<Fixture[] | null> {
  const url = new URL(filename, fixturesDirectory)
  try { await access(url) } catch { return null }
  const records = JSON.parse(await readFile(url, 'utf8'))
  if (!Array.isArray(records)) throw new Error(`${filename} doit contenir un tableau`)
  for (const record of records) {
    if (!record || typeof record.id !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$/.test(record.id)) {
      throw new Error(`Identifiant de document invalide dans ${filename}`)
    }
  }
  return records
}

async function buildWrites(seedDay: number): Promise<{ writes: Write[], counts: Record<string, number> }> {
  const writes: Write[] = []
  const counts: Record<string, number> = {}
  const add = (collection: string, path: string, data: DocumentData) => {
    writes.push({ path, data })
    counts[collection] = (counts[collection] ?? 0) + 1
  }

  const catalog = await readCatalog(fixturesDirectory, seedDay)
  for (const [collection, documents] of Object.entries(catalog)) {
    for (const document of documents) add(collection, `${collection}/${document.id}`, document)
  }

  for (const collection of ['users', 'groups'] as const) {
    for (const document of await readOptional(`${collection}.json`) ?? []) {
      add(collection, `${collection}/${document.id}`, document)
    }
  }

  for (const { slotTemplates, ...point } of await readOptional('pickupPoints.json') ?? []) {
    const slots = (Array.isArray(slotTemplates) ? slotTemplates : []).map((template) => {
      const [startHour, startMinute] = hhmm(template.start)
      const [endHour, endMinute] = hhmm(template.end)
      return {
        start: montrealTime(seedDay, template.inDays, startHour, startMinute),
        end: montrealTime(seedDay, template.inDays, endHour, endMinute)
      }
    })
    add('pickupPoints', `pickupPoints/${point.id}`, { ...point, slots })
  }

  // households.json (B-028) : le ménage, son document privé et son adhésion au groupe.
  for (const { private: privateProfile, memberRole, ...household } of await readOptional('households.json') ?? []) {
    add('households', `households/${household.id}`, household)
    if (privateProfile && typeof privateProfile === 'object') {
      add('households/private', `households/${household.id}/private/profile`, privateProfile as DocumentData)
    }
    if (typeof household.groupId === 'string') {
      add('groups/members', `groups/${household.groupId}/members/${household.id}`, {
        householdId: household.id,
        role: memberRole === 'coordinator' ? 'coordinator' : 'member',
        joinedAt: Timestamp.fromMillis(seedDay - 14 * millisecondsPerDay)
      })
    }
  }

  // groupOrders.json (B-028) : la commande, ses créneaux et ses parts.
  for (const { shares, pickupSlotsInDays, ...order } of await readOptional('groupOrders.json') ?? []) {
    const pickupSlots = (Array.isArray(pickupSlotsInDays) ? pickupSlotsInDays : []).map((slot) => ({
      start: montrealTime(seedDay, slot.inDays, slot.startHour, 0),
      end: montrealTime(seedDay, slot.inDays, slot.endHour, 0)
    }))
    add('groupOrders', `groupOrders/${order.id}`, { ...order, pickupSlots })
    for (const share of Array.isArray(shares) ? shares : []) {
      add('groupOrders/shares', `groupOrders/${order.id}/shares/${share.householdId}`, share)
    }
  }

  return { writes, counts }
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
  const { writes, counts } = await buildWrites(seedDay)
  const summary = Object.entries(counts).map(([name, count]) => `${name}: ${count}`).join(', ')

  if (values['dry-run']) {
    console.log(`[dry-run] ${writes.length} documents : ${summary}`)
    return
  }

  let credential: Credential | undefined
  if (values.target === 'emulator') {
    const host = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080'
    if (!/^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(host)) throw new Error('FIRESTORE_EMULATOR_HOST doit être local')
    process.env.FIRESTORE_EMULATOR_HOST = host
    console.log(`Cible : émulateur ${host}, projet ${projectId}`)
  } else {
    delete process.env.FIRESTORE_EMULATOR_HOST
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
  } finally {
    await db.terminate()
    await deleteApp(app)
  }
}

seedFirestore().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error)
  process.exitCode = 1
})
