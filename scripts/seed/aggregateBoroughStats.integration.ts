import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { deleteApp, initializeApp } from 'firebase-admin/app'
import { getFirestore } from 'firebase-admin/firestore'

test('agrégation des arrondissements : dry-run sans écriture, puis --yes, puis idempotent', async (t) => {
  const projectId = 'demo-grenier-borough-test'
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? '', /^127\.0\.0\.1:[0-9]+$/, 'Lancer avec firebase emulators:exec')
  process.env.METADATA_SERVER_DETECTION = 'none'
  const app = initializeApp({ projectId }, 'borough-test')
  const db = getFirestore(app)
  t.after(async () => { await db.terminate(); await deleteApp(app) })

  await db.doc('products/p1').set({ id: 'p1', referenceGroceryPriceCents: 1_500 })
  await db.doc('offers/o-1').set({ id: 'o-1', productId: 'p1' })
  await db.doc('groups/g-sm').set({ id: 'g-sm', neighborhood: 'Saint-Michel' })
  await db.doc('groups/g-ver').set({ id: 'g-ver', neighborhood: 'Verdun' })
  const joinedAt = new Date()
  for (const household of ['h1', 'h2', 'h3']) await db.doc(`groups/g-sm/members/${household}`).set({ householdId: household, role: 'member', joinedAt })
  await db.doc('groups/g-ver/members/h9').set({ householdId: 'h9', role: 'member', joinedAt })
  await db.doc('groupOrders/order-1').set({ id: 'order-1', groupId: 'g-sm', offerId: 'o-1', status: 'closed' })
  await db.doc('groupOrders/order-open').set({ id: 'order-open', groupId: 'g-sm', offerId: 'o-1', status: 'open' })
  await db.doc('groupOrders/order-1/shares/h1').set({ householdId: 'h1', quantity: 2, finalPriceCents: 2_000, suspendedAmountCents: 500, subsidyCents: 0 })
  await db.doc('groupOrders/order-1/shares/h2').set({ householdId: 'h2', quantity: 1, finalPriceCents: 1_000, suspendedAmountCents: 0, subsidyCents: 400 })
  await db.doc('groupOrders/order-open/shares/h3').set({ householdId: 'h3', quantity: 1, suspendedAmountCents: 0, subsidyCents: 0 })
  // Ancien document d'un arrondissement sous le seuil : supprimé.
  await db.doc('boroughStats/verdun').set({ id: 'verdun', households: 1 })

  const script = fileURLToPath(new URL('./aggregateBoroughStats.ts', import.meta.url))
  const run = (...args: string[]) =>
    execFileSync(process.execPath, [script, '--project', projectId, ...args], { env: process.env, encoding: 'utf8', timeout: 60_000, stdio: 'pipe' })
  const id = 'villeray-saint-michel-parc-extension'

  assert.match(run(), /À écrire : 1 arrondissement/)
  assert.equal((await db.doc(`boroughStats/${id}`).get()).exists, false)
  assert.equal((await db.doc('boroughStats/verdun').get()).exists, true)

  assert.match(run('--yes'), /Écrits : 1 arrondissement/)
  const first = (await db.doc(`boroughStats/${id}`).get()).data()!
  assert.equal(first.households, 3)
  assert.equal(first.activeHouseholds, 2)
  assert.equal(first.groupCount, 1)
  assert.equal(first.savingsCents, 1_000 + 500)
  assert.equal(first.basketsOffered, 0)
  assert.equal(first.familiesHelped, 1)
  assert.equal(first.name, 'Villeray–Saint-Michel–Parc-Extension')
  assert.ok(first.updatedAt.toDate() instanceof Date)
  assert.equal((await db.doc('boroughStats/verdun').get()).exists, false)
  assert.deepEqual(Object.keys(first).sort(), ['activeHouseholds', 'basketsOffered', 'centerGeohash', 'familiesHelped', 'groupCount',
    'households', 'id', 'name', 'neighborhoods', 'savingsCents', 'shortName', 'updatedAt'])

  run('--yes')
  const second = (await db.doc(`boroughStats/${id}`).get()).data()!
  assert.deepEqual({ ...second, updatedAt: 0 }, { ...first, updatedAt: 0 })
})
