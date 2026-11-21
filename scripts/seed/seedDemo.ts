import { open, unlink } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { parseArgs } from 'node:util'
import { deleteApp, initializeApp } from 'firebase-admin/app'
import { getFirestore } from 'firebase-admin/firestore'
import { millisecondsPerDay, readCatalog } from './catalog.ts'

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

  const seedDay = Math.floor(Date.now() / millisecondsPerDay) * millisecondsPerDay
  const catalog = await readCatalog(new URL('./fixtures/', import.meta.url), seedDay)
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
    try {
      await db.collection('vendors').limit(1).get()

      const batch = db.batch()
      for (const [collection, documents] of Object.entries(catalog)) {
        for (const document of documents) {
          batch.set(db.collection(collection).doc(document.id), document)
        }
      }

      console.log(`Réinitialisation des émulateurs Firestore et Auth pour ${projectId}`)
      await emulatorRequest(`${authProject}/accounts`, 'DELETE')
      await emulatorRequest(`http://${firestoreHost}/emulator/v1/${databasePath}`, 'DELETE')
      await batch.commit()
      console.log(`Catalogue chargé : ${catalog.vendors.length} vendeurs, ${catalog.products.length} produits, ${catalog.offers.length} lots.`)
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
