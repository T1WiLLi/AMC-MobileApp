import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { deleteApp, initializeApp } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { getFirestore, Timestamp } from 'firebase-admin/firestore'
import { millisecondsPerDay } from './catalog.ts'

test('resets both emulators and restores the same demo data and persona accounts on a second run', async (t) => {
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

  const signIn = async (email: string, password: string) => {
    const response = await fetch(
      `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-key`,
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) }
    )
    assert.equal(response.status, 200, `connexion de ${email}`)
    return ((await response.json()) as { localId: string }).localId
  }

  const timestampDay = (value: unknown) => {
    assert.ok(value instanceof Timestamp)
    return Math.floor(value.toMillis() / millisecondsPerDay)
  }

  const runAndReadSeed = async (password?: string) => {
    const startDay = Math.floor(Date.now() / millisecondsPerDay)
    const env = { ...process.env }
    delete env.GRENIER_DEMO_PASSWORD
    if (password) {
      env.GRENIER_DEMO_PASSWORD = password
    }
    const output = run(projectId, env)
    const endDay = Math.floor(Date.now() / millisecondsPerDay)
    await assert.rejects(auth.getUser(staleUser), { code: 'auth/user-not-found' })
    assert.equal((await staleDoc.get()).exists, false)

    const users: { id: string }[] = JSON.parse(await readFile(new URL('./fixtures/users.json', import.meta.url), 'utf8'))
    assert.equal((await auth.listUsers()).users.length, users.length)
    const generated = /Mot de passe généré[^:]*: (\S+)/.exec(output)?.[1]
    if (password) {
      assert.equal(generated, undefined)
      assert.equal(output.includes(password), false)
    }
    const accountPassword = password ?? generated
    assert.ok(accountPassword, 'le mot de passe généré doit être affiché')
    for (const [uid, email] of [
      ['user-amina', 'amina@demo.grenier.local'],
      ['user-ferme-lafleur', 'ferme-lafleur@demo.grenier.local'],
      ['user-jean', 'jean@demo.grenier.local']
    ]) {
      assert.equal((await auth.getUser(uid)).email, email)
      assert.equal(await signIn(email, accountPassword), uid)
    }

    const roots = await Promise.all(
      ['vendors', 'products', 'offers', 'groups', 'pickupPoints', 'users', 'households', 'groupOrders'].map(async (name) => {
        const fixtures: { id: string; deadlineInDays?: number }[] = JSON.parse(
          await readFile(new URL(`./fixtures/${name}.json`, import.meta.url), 'utf8')
        )
        const snapshot = await db.collection(name).get()
        assert.deepEqual(snapshot.docs.map((doc) => doc.id).sort(), fixtures.map(({ id }) => id).sort())
        const offsetById = new Map(fixtures.map(({ id, deadlineInDays }) => [id, deadlineInDays]))
        return snapshot.docs.map((doc) => {
          const data = doc.data()
          for (const field of ['deadlineInDays', 'slotTemplates', 'pickupSlotsInDays', 'shares', 'private', 'memberRole']) {
            assert.equal(Object.hasOwn(data, field), false, `${name}/${doc.id}.${field}`)
          }
          if (name === 'offers') {
            const { deadline, ...offer } = data
            const offset = offsetById.get(doc.id)
            assert.equal(typeof offset, 'number')
            assert.ok([startDay, endDay].includes(timestampDay(deadline) - Number(offset)))
            assert.equal(deadline.toMillis() % millisecondsPerDay, 0)
            return offer
          }
          const slotsField = name === 'pickupPoints' ? 'slots' : name === 'groupOrders' ? 'pickupSlots' : undefined
          if (!slotsField) {
            return data
          }
          const { [slotsField]: slots, ...rest } = data
          assert.ok(Array.isArray(slots) && slots.length > 0)
          for (const { start, end } of slots) {
            assert.ok(timestampDay(start) > startDay && start.toMillis() < end.toMillis())
          }
          return rest
        })
      })
    )

    const members = await db.collectionGroup('members').get()
    const profiles = await db.collectionGroup('private').get()
    const shares = await db.collectionGroup('shares').get()
    const orders: { shares: unknown[] }[] = JSON.parse(await readFile(new URL('./fixtures/groupOrders.json', import.meta.url), 'utf8'))
    assert.equal(members.size, 60)
    assert.equal(profiles.size, 60)
    assert.equal(shares.size, orders.reduce((total, order) => total + order.shares.length, 0))
    assert.ok((await db.doc('groups/group-parc-extension/members/household-amina').get()).exists)
    assert.ok((await db.doc('households/household-amina/private/profile').get()).exists)
    const subcollections = [members, profiles, shares].map((snapshot) => snapshot.docs.map((doc) => {
      const { joinedAt, ...data } = doc.data()
      if (joinedAt !== undefined) {
        assert.ok([startDay, endDay].includes(timestampDay(joinedAt)))
      }
      return { path: doc.ref.path, data }
    }).sort((left, right) => left.path.localeCompare(right.path)))
    return [...roots, ...subcollections]
  }

  const firstRun = await runAndReadSeed('seed-test-password')

  await staleDoc.set({ removeMe: true })
  await auth.createUser({ uid: staleUser })
  const secondRun = await runAndReadSeed()
  assert.deepEqual(secondRun, firstRun)
})
