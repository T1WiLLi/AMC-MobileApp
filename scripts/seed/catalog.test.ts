import assert from 'node:assert/strict'
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { test } from 'node:test'
import { Timestamp } from 'firebase-admin/firestore'
import { millisecondsPerDay, readCatalog } from './catalog.ts'

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
