import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { deleteApp, initializeApp } from 'firebase-admin/app'
import { getFirestore } from 'firebase-admin/firestore'

test('rattrapage des userId : dry-run sans écriture, puis --yes, puis idempotent', async (t) => {
  const projectId = 'demo-grenier-backfill-test'
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:[0-9]+$/, 'Lancer avec firebase emulators:exec')
  process.env.METADATA_SERVER_DETECTION = 'none'
  const app = initializeApp({ projectId }, 'backfill-test')
  const db = getFirestore(app)
  t.after(async () => { await db.terminate(); await deleteApp(app) })

  await db.doc('households/h-owner').set({ id: 'h-owner', userIds: ['u-a', 'u-b'], ownerId: 'u-b' })
  await db.doc('households/h-legacy').set({ id: 'h-legacy', userIds: ['u-c'] })
  await db.doc('households/h-empty').set({ id: 'h-empty', userIds: [] })
  const joinedAt = new Date()
  await db.doc('groups/g1/members/h-owner').set({ householdId: 'h-owner', role: 'coordinator', joinedAt })
  await db.doc('groups/g1/members/h-legacy').set({ householdId: 'h-legacy', role: 'member', joinedAt })
  await db.doc('groups/g1/members/h-empty').set({ householdId: 'h-empty', role: 'member', joinedAt })
  await db.doc('groups/g1/members/h-missing').set({ householdId: 'h-missing', role: 'member', joinedAt })
  await db.doc('groups/g2/members/h-owner').set({ householdId: 'h-owner', role: 'member', joinedAt, userId: 'deja' })

  const script = fileURLToPath(new URL('./backfillMemberUserId.ts', import.meta.url))
  const run = (...args: string[]) =>
    execFileSync(process.execPath, [script, '--project', projectId, ...args], { env: process.env, encoding: 'utf8', timeout: 60_000, stdio: 'pipe' })
  const userId = async (path: string) => (await db.doc(path).get()).data()?.userId

  const dry = run()
  assert.match(dry, /À mettre à jour : 2/)
  assert.equal(await userId('groups/g1/members/h-owner'), undefined)

  const applied = run('--yes')
  assert.match(applied, /Mises à jour : 2/)
  assert.match(applied, /introuvable : 1/)
  assert.match(applied, /sans compte : 1/)
  assert.equal(await userId('groups/g1/members/h-owner'), 'u-b')
  assert.equal(await userId('groups/g1/members/h-legacy'), 'u-c')
  assert.equal(await userId('groups/g1/members/h-empty'), undefined)
  assert.equal(await userId('groups/g2/members/h-owner'), 'deja')
  // Les autres champs ne bougent pas.
  assert.equal((await db.doc('groups/g1/members/h-owner').get()).data()?.role, 'coordinator')

  assert.match(run('--yes'), /Mises à jour : 0/)
})
