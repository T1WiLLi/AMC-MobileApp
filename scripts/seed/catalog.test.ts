import assert from 'node:assert/strict'
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { test } from 'node:test'
import { Timestamp } from 'firebase-admin/firestore'
import { demoAccounts, millisecondsPerDay, montrealTime, personaUserIds, readCatalog, readDemoSeed } from './catalog.ts'

test('loads stable document IDs and translates offer deadlines to Firestore timestamps', async () => {
  const start = Date.UTC(2026, 10, 21)
  const catalog = await readCatalog(new URL('./fixtures/', import.meta.url), start)
  assert.ok(catalog.vendors.length > 0)
  assert.ok(catalog.products.length > 0)
  assert.ok(catalog.offers.length > 0)

  const rawOffers = (await import('./fixtures/offers.json', { with: { type: 'json' } })).default
  const offer = catalog.offers[0]
  assert.equal(offer.id, rawOffers[0].id)
  assert.deepEqual(offer.deadline, Timestamp.fromMillis(start + rawOffers[0].deadlineInDays * millisecondsPerDay))
  assert.equal(Object.hasOwn(offer, 'deadlineInDays'), false)
})

test('rejects an incomplete catalog and duplicate document IDs', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'grenier-catalog-'))
  t.after(() => rm(directory, { recursive: true, force: true }))
  const fixtures = pathToFileURL(directory + '/')

  await writeFile(join(directory, 'vendors.json'), '[{"id":"vendor"}]')
  await assert.rejects(readCatalog(fixtures, 0), /products\.json|offers\.json/)
  await writeFile(join(directory, 'products.json'), '[{"id":"same"},{"id":"same"}]')
  await writeFile(join(directory, 'offers.json'), '[{"id":"offer","deadlineInDays":1}]')
  await assert.rejects(readCatalog(fixtures, 0), /products\.json.*same/)
})


test('rejects products that refer to missing vendors before returning a seed plan', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'grenier-catalog-'))
  t.after(() => rm(directory, { recursive: true, force: true }))
  const source = new URL('./fixtures/', import.meta.url)

  for (const name of ['vendors.json', 'products.json', 'offers.json']) {
    const fixtures = JSON.parse(await readFile(new URL(name, source), 'utf8'))
    if (name === 'products.json') {
      fixtures[0].vendorId = 'missing-vendor'
    }
    await writeFile(join(directory, name), JSON.stringify(fixtures))
  }

  await assert.rejects(readCatalog(pathToFileURL(directory + '/'), 0), /products.*vendorId invalide/)
})

async function copyFixtures(directory: string, edit: (name: string, fixtures: any[]) => void = () => {}) {
  const source = new URL('./fixtures/', import.meta.url)
  for (const name of ['vendors', 'products', 'offers', 'groups', 'pickupPoints', 'users', 'households', 'groupOrders']) {
    const fixtures = JSON.parse(await readFile(new URL(`${name}.json`, source), 'utf8'))
    edit(name, fixtures)
    await writeFile(join(directory, `${name}.json`), JSON.stringify(fixtures))
  }
}

test('converts Montréal wall-clock times across daylight saving time', () => {
  assert.equal(montrealTime(Date.UTC(2026, 10, 21), 17 * 60), Date.UTC(2026, 10, 21, 22))
  assert.equal(montrealTime(Date.UTC(2026, 6, 1), 17 * 60 + 30), Date.UTC(2026, 6, 1, 21, 30))
  assert.equal(montrealTime(Date.UTC(2026, 10, 1), 10 * 60), Date.UTC(2026, 10, 1, 15))
})

test('loads groups, pickup points, users, households and group orders in the app format', async () => {
  const start = Date.UTC(2026, 10, 21)
  const seed = await readDemoSeed(new URL('./fixtures/', import.meta.url), start, { rich: false })
  const raw = async (name: string) => JSON.parse(await readFile(new URL(`./fixtures/${name}.json`, import.meta.url), 'utf8'))
  const [rawPickups, rawUsers, rawOrders] = await Promise.all([raw('pickupPoints'), raw('users'), raw('groupOrders')])

  assert.equal(seed.groups.length, 9)
  assert.equal(seed.pickupPoints.length, 9)
  assert.equal(seed.users.length, rawUsers.length)
  assert.equal(seed.households.length, 60)
  assert.equal(seed.householdProfiles.length, 60)
  assert.equal(seed.members.length, 60)
  assert.equal(seed.groupOrders.length, rawOrders.length)
  const rawShares = rawOrders.flatMap((order: any) => order.shares)
  assert.equal(seed.shares.length, rawShares.length)

  const jeanPoint = seed.pickupPoints.find(({ id }) => id === 'pickup-parc-extension-1')!
  assert.equal(Object.hasOwn(jeanPoint, 'slotTemplates'), false)
  assert.equal(jeanPoint.hostUserId, 'user-jean')
  assert.deepEqual(rawPickups.find(({ id }: any) => id === jeanPoint.id).slotTemplates[0],
    { inDays: 2, start: '17:00', end: '19:30' })
  assert.deepEqual(jeanPoint.slots[0], {
    start: Timestamp.fromMillis(Date.UTC(2026, 10, 23, 22)),
    end: Timestamp.fromMillis(Date.UTC(2026, 10, 24, 0, 30))
  })

  const order = seed.groupOrders[0]
  const rawSlot = rawOrders[0].pickupSlotsInDays[0]
  assert.equal(Object.hasOwn(order, 'pickupSlotsInDays'), false)
  assert.equal(Object.hasOwn(order, 'shares'), false)
  assert.deepEqual(order.pickupSlots[0].start,
    Timestamp.fromMillis(montrealTime(start + rawSlot.inDays * millisecondsPerDay, rawSlot.startHour * 60)))

  const amina = seed.households.find(({ id }) => id === 'household-amina')!
  for (const field of ['groupId', 'memberRole', 'private']) {
    assert.equal(Object.hasOwn(amina, field), false, field)
  }
  const paths = new Set(seed.documents.map(({ path }) => path))
  assert.equal(paths.size, seed.documents.length)
  for (const path of [
    'groups/group-parc-extension', 'pickupPoints/pickup-parc-extension-1', 'users/user-amina',
    'households/household-amina', 'households/household-amina/private/profile',
    'groups/group-parc-extension/members/household-amina', `groupOrders/${order.id}`,
    `groupOrders/${order.id}/shares/${rawOrders[0].shares[0].householdId}`, 'offers/' + seed.offers[0].id
  ]) {
    assert.ok(paths.has(path), path)
  }
  const member = seed.documents.find(({ path }) => path === 'groups/group-parc-extension/members/household-amina')!
  assert.deepEqual(member.data, { householdId: 'household-amina', role: 'member', joinedAt: Timestamp.fromMillis(start) })
  const profile = seed.documents.find(({ path }) => path === 'households/household-amina/private/profile')!
  assert.deepEqual(profile.data, { isSubsidized: false })
  const share = seed.documents.find(({ path }) => path.startsWith(`groupOrders/${order.id}/shares/`))!
  assert.deepEqual(share.data, rawOrders[0].shares[0])
  assert.equal(seed.documents.length, 6 + 40 + 25 + 9 + 9 + rawUsers.length + 60 * 3 + rawOrders.length + rawShares.length)
})

test('creates one demo account per user, including the three personas', async () => {
  const seed = await readDemoSeed(new URL('./fixtures/', import.meta.url), 0)
  const accounts = demoAccounts(seed.users)
  assert.equal(accounts.length, seed.users.length)
  assert.deepEqual(personaUserIds.map((uid) => accounts.find((account) => account.uid === uid)?.email), [
    'amina@demo.grenier.local', 'ferme-lafleur@demo.grenier.local', 'jean@demo.grenier.local'
  ])
  assert.equal(new Set(accounts.map(({ email }) => email)).size, accounts.length)
  for (const account of accounts) {
    assert.equal(Object.hasOwn(account, 'password'), false)
  }
})

test('rejects inconsistent memberships and shares before returning a seed plan', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'grenier-seed-'))
  t.after(() => rm(directory, { recursive: true, force: true }))
  const fixtures = pathToFileURL(directory + '/')

  await copyFixtures(directory, (name, records) => {
    if (name === 'households') {
      records.find(({ id }) => id === 'household-amina').groupId = 'group-rosemont'
    }
  })
  await assert.rejects(readDemoSeed(fixtures, 0, { rich: false }), /householdCount/)

  await copyFixtures(directory, (name, records) => {
    if (name === 'groupOrders') {
      records[0].shares.push({ ...records[0].shares[0] })
    }
  })
  await assert.rejects(readDemoSeed(fixtures, 0, { rich: false }), /part invalide/)

  await copyFixtures(directory, (name, records) => {
    if (name === 'users') {
      records.splice(records.findIndex(({ id }) => id === 'user-ferme-lafleur'), 1)
    }
  })
  await assert.rejects(readDemoSeed(fixtures, 0, { rich: false }), /persona user-ferme-lafleur/)

  await copyFixtures(directory, (name, records) => {
    if (name === 'pickupPoints') {
      records[0].slotTemplates[0].start = '25:00'
    }
  })
  await assert.rejects(readDemoSeed(fixtures, 0, { rich: false }), /heure invalide/)
})
