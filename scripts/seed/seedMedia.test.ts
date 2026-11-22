import assert from 'node:assert/strict'
import { test } from 'node:test'
import { familyImage, GROUP_NEIGHBORHOODS, planMediaWrites, SEED_VENDOR_PHOTO_ID, vendorImage, type Inventory } from './seedMedia.ts'

const empty: Inventory = { groups: [], vendors: [], households: [], organizations: [] }
const plan = (inventory: Partial<Inventory>, options: Parameters<typeof planMediaWrites>[1] = {}) =>
  planMediaWrites({ ...empty, ...inventory }, options)

test('groupe sans photo ni bannière : deux écritures avec le champ parent', () => {
  const writes = plan({ groups: [{ id: 'g1', neighborhood: 'verdun', hasPhoto: false, hasBanner: false }] })
  assert.deepEqual(writes.map(({ path }) => path), ['groups/g1/media/photo', 'groups/g1/media/banner'])
  assert.deepEqual(writes[0].parent, { path: 'groups/g1', field: 'photoUpdatedAt' })
  assert.deepEqual(writes[1].parent, { path: 'groups/g1', field: 'bannerUpdatedAt' })
  assert.equal(writes[0].image.file, 'groups/verdun-photo.jpg')
  assert.equal(writes[1].image.file, 'groups/verdun-banner.jpg')
})

test('groupe qui a déjà photo et bannière : rien, sauf avec force', () => {
  const groups = [{ id: 'g1', neighborhood: 'verdun', hasPhoto: true, hasBanner: true }]
  assert.equal(plan({ groups }).length, 0)
  assert.equal(plan({ groups }, { force: true }).length, 2)
})

test('groupe avec seulement la photo : seule la bannière est écrite', () => {
  const writes = plan({ groups: [{ id: 'g1', neighborhood: 'verdun', hasPhoto: true, hasBanner: false }] })
  assert.deepEqual(writes.map(({ path }) => path), ['groups/g1/media/banner'])
})

test("groupe dont le quartier n'est pas disponible : ignoré", () => {
  const groups = [{ id: 'g1', neighborhood: 'verdun', hasPhoto: false, hasBanner: false }]
  assert.equal(plan({ groups }, { availableGroups: new Set(['mile-end']) }).length, 0)
  assert.equal(plan({ groups: [{ ...groups[0], neighborhood: 'inconnu' }] }).length, 0)
  assert.ok(GROUP_NEIGHBORHOODS.includes('verdun'))
})

test('vendeur sans photo ou avec un file:// : une écriture photo-seed + photoURLs', () => {
  for (const photoURLs of [[], ['file:///var/mobile/x.jpg']]) {
    const writes = plan({ vendors: [{ id: 'vendor-ferme-lafleur', kind: 'farm', photoURLs }] })
    assert.equal(writes.length, 1)
    assert.equal(writes[0].path, `vendors/vendor-ferme-lafleur/media/${SEED_VENDOR_PHOTO_ID}`)
    assert.deepEqual(writes[0].parent, { path: 'vendors/vendor-ferme-lafleur', field: 'photoURLs' })
    assert.equal(writes[0].image.file, 'vendors/ferme-lafleur.jpg')
  }
})

test("vendeur avec une photo grenier-media qui n'est pas du seed : ignoré même avec force", () => {
  const vendors = [{ id: 'v1', kind: 'farm', photoURLs: ['grenier-media:///vendors/v1/media/photo-abc?v=1'] }]
  assert.equal(plan({ vendors }).length, 0)
  assert.equal(plan({ vendors }, { force: true }).length, 0)
})

test('vendeur avec une photo du seed : remplacée seulement avec force', () => {
  const vendors = [{ id: 'v1', kind: 'farm', photoURLs: [`grenier-media:///vendors/v1/media/${SEED_VENDOR_PHOTO_ID}?v=1`] }]
  assert.equal(plan({ vendors }).length, 0)
  assert.equal(plan({ vendors }, { force: true }).length, 1)
})

test('image de vendeur : par id connu, sinon par type', () => {
  assert.equal(vendorImage('vendor-marche-central', 'other').file, 'vendors/marche-central.jpg')
  assert.equal(vendorImage('x', 'bakery').file, 'vendors/fournil-terrebonne.jpg')
  assert.match(vendorImage('x', 'farm').file, /^vendors\/farm-[ab]\.jpg$/)
})

test('ménages sans photo : households/{id}/media/photo, image de famille stable', () => {
  const writes = plan({ households: [{ id: 'h1', hasPhoto: false }, { id: 'h2', hasPhoto: true }] })
  assert.deepEqual(writes.map(({ path }) => path), ['households/h1/media/photo'])
  assert.equal(writes[0].parent, undefined)
  assert.equal(plan({ households: [{ id: 'h2', hasPhoto: true }] }, { force: true }).length, 1)
  assert.deepEqual(familyImage('h1'), familyImage('h1'))
  for (const id of ['a', 'b', 'household-1', 'zzz', 'h1', 'h2', 'h3', 'h4', 'h5']) {
    assert.match(familyImage(id).file, /^families\/family-0[1-8]\.jpg$/)
  }
})

test('organismes sans logo : organizations/{id}/media/logo', () => {
  const writes = plan({ organizations: [{ id: 'o1', hasLogo: false }, { id: 'o2', hasLogo: true }] })
  assert.deepEqual(writes.map(({ path }) => path), ['organizations/o1/media/logo'])
  assert.equal(plan({ organizations: [{ id: 'o2', hasLogo: true }] }, { force: true }).length, 1)
})
