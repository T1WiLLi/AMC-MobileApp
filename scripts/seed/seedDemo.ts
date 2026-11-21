import { randomBytes } from 'node:crypto'
import { open, unlink } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { parseArgs } from 'node:util'
import { deleteApp, initializeApp } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { getFirestore } from 'firebase-admin/firestore'
import { demoAccounts, millisecondsPerDay, personaUserIds, readDemoSeed } from './catalog.ts'

function loopbackHost(variable: string, port: number): string {
  const value = process.env[variable] ?? `127.0.0.1:${port}`
  const match = /^(?:127\.0\.0\.1|localhost):([1-9][0-9]{0,4})$/.exec(value)
  if (!match || Number(match[1]) > 65535) {
    throw new Error(`${variable} doit désigner un port local (127.0.0.1 ou localhost)`)
  }
  return `127.0.0.1:${match[1]}`
}

async function emulatorRequest(url: string, method: 'GET' | 'DELETE') {
  const response = await fetch(url, {
    method,
    headers: { Authorization: 'Bearer owner' },
    redirect: 'error',
    signal: AbortSignal.timeout(15_000)
  })
  await response.body?.cancel()
  if (!response.ok) {
    throw new Error(`${method} ${url} a échoué (HTTP ${response.status})`)
  }
}

async function seedDemo() {
  const { values } = parseArgs({ options: { project: { type: 'string' } } })
  const projectId = values.project ?? 'demo-grenier'
  if (!/^demo-[a-z0-9][a-z0-9-]{0,23}$/.test(projectId) || projectId.endsWith('-')) {
    throw new Error('Le projet doit être un identifiant local demo-*')
  }
  if (process.env.GCLOUD_PROJECT && process.env.GCLOUD_PROJECT !== projectId) {
    throw new Error(`GCLOUD_PROJECT diffère de la cible ${projectId}`)
  }

  const firestoreHost = loopbackHost('FIRESTORE_EMULATOR_HOST', 8080)
  const authHost = loopbackHost('FIREBASE_AUTH_EMULATOR_HOST', 9099)
  process.env.FIRESTORE_EMULATOR_HOST = firestoreHost
  process.env.FIREBASE_AUTH_EMULATOR_HOST = authHost

  process.env.METADATA_SERVER_DETECTION = 'none'

  // Mot de passe commun des comptes de démo : jamais dans le dépôt.
  const configuredPassword = process.env.GRENIER_DEMO_PASSWORD
  if (configuredPassword !== undefined && configuredPassword.length < 6) {
    throw new Error('GRENIER_DEMO_PASSWORD doit compter au moins 6 caractères')
  }
  const password = configuredPassword ?? randomBytes(12).toString('base64url')

  const seedDay = Math.floor(Date.now() / millisecondsPerDay) * millisecondsPerDay
  const seed = await readDemoSeed(new URL('./fixtures/', import.meta.url), seedDay)
  const accounts = demoAccounts(seed.users)
  const databasePath = `projects/${projectId}/databases/(default)/documents`
  const authProject = `http://${authHost}/emulator/v1/projects/${projectId}`

  const lockPath = join(tmpdir(), `grenier-seed-${projectId}.lock`)
  const lock = await open(lockPath, 'wx').catch((error) => {
    throw new Error(`Impossible de prendre le verrou de seed : ${lockPath}`, { cause: error })
  })
  try {
    await lock.writeFile(String(process.pid))
    await Promise.all([
      emulatorRequest(`http://${firestoreHost}/v1/${databasePath}/vendors?pageSize=1`, 'GET'),
      emulatorRequest(`${authProject}/config`, 'GET')
    ])

    const app = initializeApp({ projectId })
    const db = getFirestore(app)
    const auth = getAuth(app)
    try {
      await db.collection('vendors').limit(1).get()

      const batch = db.batch()
      for (const { path, data } of seed.documents) {
        batch.set(db.doc(path), data)
      }

      console.log(`Réinitialisation des émulateurs Firestore et Auth pour ${projectId}`)
      await emulatorRequest(`${authProject}/accounts`, 'DELETE')
      await emulatorRequest(`http://${firestoreHost}/emulator/v1/${databasePath}`, 'DELETE')
      await batch.commit()
      console.log(`Catalogue chargé : ${seed.vendors.length} vendeurs, ${seed.products.length} produits, ${seed.offers.length} lots.`)
      console.log(`Communauté chargée : ${seed.groups.length} groupes, ${seed.pickupPoints.length} points de cueillette, ` +
        `${seed.users.length} utilisateurs, ${seed.households.length} ménages, ` +
        `${seed.groupOrders.length} commandes groupées, ${seed.shares.length} parts.`)

      for (const account of accounts) {
        await auth.createUser({ ...account, password, emailVerified: true })
      }
      console.log(`${accounts.length} comptes Auth créés. Personas :`)
      for (const account of accounts.filter(({ uid }) => (personaUserIds as readonly string[]).includes(uid))) {
        console.log(`  ${account.displayName} : ${account.email}`)
      }
      console.log(configuredPassword === undefined
        ? `Mot de passe généré pour ces comptes (émulateur local seulement) : ${password}`
        : 'Mot de passe : valeur de GRENIER_DEMO_PASSWORD')
    } finally {
      await db.terminate()
      await deleteApp(app)
    }
  } finally {
    await lock.close()
    await unlink(lockPath)
  }
}

seedDemo().catch((error: unknown) => {
  console.error(error)
  process.exitCode = 1
})
