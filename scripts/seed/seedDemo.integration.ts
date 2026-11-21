import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { deleteApp, initializeApp } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { getFirestore, Timestamp } from 'firebase-admin/firestore'
import { millisecondsPerDay } from './catalog.ts'

test('resets both emulators and restores the same catalog on a second run', async (t) => {
  const projectId = 'demo-grenier-seed-test'
  assert.equal(process.env.GCLOUD_PROJECT, projectId, 'Lancer avec firebase emulators:exec et le projet de test')
  for (const host of [process.env.FIRESTORE_EMULATOR_HOST, process.env.FIREBASE_AUTH_EMULATOR_HOST]) {
    assert.match(host ?? '', /^127\.0\.0\.1:[0-9]+$/)
  }

  process.env.METADATA_SERVER_DETECTION = 'none'
  const app = initializeApp({ projectId })
  const auth = getAuth(app)
  const db = getFirestore(app)
  t.after(async () => {
    await db.terminate()
    await deleteApp(app)
  })

  const staleDoc = db.doc('stale/root/children/example')
  const staleUser = 'seed-test-stale'
  const seedDemo = fileURLToPath(new URL('./seedDemo.ts', import.meta.url))
  const run = (project: string, env = process.env) =>
    execFileSync(process.execPath, [seedDemo, '--project', project], { env, encoding: 'utf8', timeout: 45_000, stdio: 'pipe' })

  await staleDoc.set({ removeMe: true })
  await auth.createUser({ uid: staleUser })
  assert.throws(() => run('amc-2026-8ab03'), /identifiant local demo-/)
  assert.throws(
    () => run(projectId, { ...process.env, FIREBASE_AUTH_EMULATOR_HOST: 'example.test:9099' }),
    /doit désigner un port local/
  )
  assert.throws(
    () => run(projectId, { ...process.env, FIRESTORE_EMULATOR_HOST: '127.0.0.1:1' }),
    /fetch failed/
  )
  assert.equal((await staleDoc.get()).exists, true)
  assert.equal((await auth.getUser(staleUser)).uid, staleUser)

  const runAndReadSeed = async () => {
    const startDay = Math.floor(Date.now() / millisecondsPerDay)
    run(projectId)
    const endDay = Math.floor(Date.now() / millisecondsPerDay)
    await assert.rejects(auth.getUser(staleUser), { code: 'auth/user-not-found' })
    assert.equal((await staleDoc.get()).exists, false)
    return Promise.all(['vendors', 'products', 'offers'].map(async (name) => {
      const fixtures: { id: string; deadlineInDays?: number }[] = JSON.parse(
        await readFile(new URL(`./fixtures/${name}.json`, import.meta.url), 'utf8')
      )
      const snapshot = await db.collection(name).get()
      assert.deepEqual(snapshot.docs.map((doc) => doc.id).sort(), fixtures.map(({ id }) => id).sort())
      const offsetById = new Map(fixtures.map(({ id, deadlineInDays }) => [id, deadlineInDays]))
      return snapshot.docs.map((doc) => {
        const data = doc.data()
        if (name !== 'offers') {
          return data
        }

        const { deadline, ...offer } = data
        assert.ok(deadline instanceof Timestamp)
        assert.equal(Object.hasOwn(offer, 'deadlineInDays'), false)
        const offset = offsetById.get(doc.id)
        assert.equal(typeof offset, 'number')
        const deadlineDay = deadline.toMillis() / millisecondsPerDay
        assert.ok(Number.isInteger(deadlineDay))
        assert.ok([startDay, endDay].includes(deadlineDay - Number(offset)))
        return offer
      })
    }))
  }

  const firstRun = await runAndReadSeed()

  await staleDoc.set({ removeMe: true })
  await auth.createUser({ uid: staleUser })
  const secondRun = await runAndReadSeed()
  assert.deepEqual(secondRun, firstRun)
})
