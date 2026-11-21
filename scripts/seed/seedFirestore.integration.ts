import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { deleteApp, initializeApp } from 'firebase-admin/app'
import { getAuth } from 'firebase-admin/auth'
import { getFirestore } from 'firebase-admin/firestore'

test('seeds documents and persona accounts without deleting anything, twice', async (t) => {
  // Même projet que seedDemo.integration.ts (singleProjectMode) : on repart d'émulateurs vides.
  const projectId = 'demo-grenier-seed-test'
  for (const host of [process.env.FIRESTORE_EMULATOR_HOST, process.env.FIREBASE_AUTH_EMULATOR_HOST]) {
    assert.match(host ?? '', /^127\.0\.0\.1:[0-9]+$/, 'Lancer avec firebase emulators:exec')
  }

  process.env.METADATA_SERVER_DETECTION = 'none'
  const app = initializeApp({ projectId }, 'seed-firestore-test')
  const auth = getAuth(app)
  const db = getFirestore(app)
  t.after(async () => {
    await db.terminate()
    await deleteApp(app)
  })

  const script = fileURLToPath(new URL('./seedFirestore.ts', import.meta.url))
  const run = (password?: string) => {
    const env = { ...process.env }
    delete env.GRENIER_DEMO_PASSWORD
    if (password) env.GRENIER_DEMO_PASSWORD = password
    return execFileSync(process.execPath, [script, '--project', projectId], { env, encoding: 'utf8', timeout: 60_000, stdio: 'pipe' })
  }
  const signIn = async (email: string, password: string) => {
    const response = await fetch(
      `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-key`,
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) }
    )
    return response.ok ? ((await response.json()) as { localId: string }).localId : null
  }

  for (const url of [
    `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/emulator/v1/projects/${projectId}/accounts`,
    `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectId}/databases/(default)/documents`
  ]) {
    const response = await fetch(url, { method: 'DELETE', headers: { Authorization: 'Bearer owner' } })
    assert.ok(response.ok, url)
  }

  // Données qui ne viennent pas du seed : elles doivent survivre.
  const keptDoc = db.doc('users/real-user-kept')
  await keptDoc.set({ displayName: 'Vrai compte' })
  await auth.createUser({ uid: 'real-user-kept', email: 'kept@example.test', password: 'kept-password' })

  const users: { id: string }[] = JSON.parse(await readFile(new URL('./fixtures/users.json', import.meta.url), 'utf8'))
  const personas = [
    ['user-amina', 'amina@demo.grenier.local'],
    ['user-ferme-lafleur', 'ferme-lafleur@demo.grenier.local'],
    ['user-jean', 'jean@demo.grenier.local']
  ]

  const first = run('seed-test-password')
  assert.equal(first.includes('seed-test-password'), false)
  assert.match(first, new RegExp(`${users.length} créés, 0 mis à jour`))
  for (const [uid, email] of personas) {
    assert.equal(await signIn(email, 'seed-test-password'), uid)
  }

  // Deuxième passage sans variable : mot de passe généré, comptes mis à jour, rien de supprimé.
  const second = run()
  assert.match(second, new RegExp(`0 créés, ${users.length} mis à jour`))
  const generated = /Mot de passe généré[^:]*: (\S+)/.exec(second)?.[1]
  assert.ok(generated, 'le mot de passe généré doit être affiché')
  for (const [uid, email] of personas) {
    assert.equal((await auth.getUser(uid)).email, email)
    assert.equal(await signIn(email, generated), uid)
    assert.equal(await signIn(email, 'seed-test-password'), null)
  }
  assert.equal((await auth.listUsers()).users.length, users.length + 1)
  assert.equal(await signIn('kept@example.test', 'kept-password'), 'real-user-kept')
  assert.equal((await keptDoc.get()).exists, true)
  assert.equal((await db.collection('users').get()).size, users.length + 1)
  assert.ok((await db.doc('groups/group-parc-extension/members/household-amina').get()).exists)
})
