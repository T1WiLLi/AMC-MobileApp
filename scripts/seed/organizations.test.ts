import assert from 'node:assert/strict'
import { readFile, stat } from 'node:fs/promises'
import { test } from 'node:test'
import {
  basketCount, basketPriceCents, bannerImage, buildOrganizationSeed, demoDonations, demoOrganizations, directoryCollection,
  geohashOf, logoImage, organizationId, planMemberWrites, planOrganizationMediaWrites, planOrganizationWrites, type GroupInfo
} from './organizations.ts'

const groups = JSON.parse(await readFile(new URL('./fixtures/groups.json', import.meta.url), 'utf8')) as GroupInfo[]
const docName = (path: string) => `projects/p/databases/(default)/documents/${path}`
const kinds = ['foodBank', 'communityCenter', 'foundation', 'localBusiness']

test('les groupes de démo existent dans les fixtures', () => {
  const ids = new Set(groups.map(({ id }) => id))
  for (const { groupId } of demoDonations) assert.ok(ids.has(groupId), groupId)
  for (const organization of demoOrganizations) {
    for (const { groupId } of organization.sponsorships) assert.ok(ids.has(groupId), groupId)
  }
})

test('cinq organismes : ids uniques, l\'organisme du compte de démo d\'abord, profils dans les limites des règles', () => {
  assert.equal(demoOrganizations[0].id, organizationId)
  assert.ok(demoOrganizations.length >= 4)
  assert.equal(new Set(demoOrganizations.map(({ id }) => id)).size, demoOrganizations.length)
  assert.equal(new Set(demoDonations.map(({ id }) => id)).size, demoDonations.length)
  for (const organization of demoOrganizations) {
    assert.ok(kinds.includes(organization.kind), organization.kind)
    assert.ok(organization.name.length >= 1 && organization.name.length <= 120)
    assert.ok(organization.neighborhood.length <= 60 && organization.mission.length <= 1000)
    const geohash = geohashOf(organization)
    assert.match(geohash, /^f25[0-9b-hjkmnp-z]{4}$/, `${organization.id} : ${geohash} hors de Montréal`)
  }
})

test('fiche publique : seulement nom, type, quartier, position et dates des médias (rien de privé)', () => {
  const seed = buildOrganizationSeed(groups)
  for (const organization of seed.organizations) {
    assert.deepEqual(Object.keys(organization.directory).sort(),
      ['bannerUpdatedAt', 'geohash', 'id', 'kind', 'name', 'neighborhood', 'photoUpdatedAt'])
    assert.ok(!('memberUserIds' in organization.directory))
  }
})

test('images : une photo de profil et une bannière par organisme, présentes et sous 300 Kio', async () => {
  const seed = buildOrganizationSeed(groups)
  for (const organization of seed.organizations) {
    assert.deepEqual(organization.media.map(({ path }) => path.split('/').pop()), ['logo', 'banner'])
    assert.deepEqual({ width: organization.media[0].width, height: organization.media[0].height }, logoImage)
    assert.deepEqual({ width: organization.media[1].width, height: organization.media[1].height }, bannerImage)
    for (const media of organization.media) {
      const { size } = await stat(new URL(`./media/${media.file}`, import.meta.url))
      assert.ok(size > 0 && size <= 300 * 1024, `${media.file} : ${size} octets`)
    }
  }
  const writes = planOrganizationMediaWrites(seed, () => Buffer.from([0xff, 0xd8, 0xff]), docName)
  assert.equal(writes.length, seed.organizations.length * 2)
  for (const write of writes) {
    assert.deepEqual(Object.keys(write.update.fields).sort(), ['contentType', 'data', 'height', 'updatedAt', 'width'])
  }
  assert.throws(() => planOrganizationMediaWrites(seed, () => Buffer.alloc(300 * 1024 + 1), docName))
})

test('dons : montants entiers positifs, dans les limites des règles, paniers et ménages cohérents', () => {
  const seed = buildOrganizationSeed(groups)
  assert.equal(seed.donations.length, demoDonations.length)
  for (const { path, data } of seed.donations) {
    assert.ok(Number.isInteger(data.amountCents) && data.amountCents >= 1 && data.amountCents <= 500_000)
    assert.ok(data.basketCount >= 0 && data.householdsReached >= 0 && data.householdsReached <= data.basketCount)
    assert.ok(path.startsWith(`organizations/${data.organizationId}/donations/`))
    assert.equal(data.isSimulated, true)
    assert.equal(data.basketCount, basketCount(data))
  }
})

test('chaque fonds : une contribution par don du groupe, solde = somme des dons, parrains cohérents', () => {
  const seed = buildOrganizationSeed(groups)
  const fundGroups = new Set(seed.funds.map(({ groupId }) => groupId))
  for (const { data } of seed.donations) assert.ok(fundGroups.has(data.groupId), `${data.groupId} sans fonds`)
  for (const fund of seed.funds) {
    const donations = seed.donations.filter(({ data }) => data.groupId === fund.groupId)
    assert.equal(fund.data.entries.length, donations.length)
    assert.equal(fund.data.entries.reduce((sum, { amountCents }) => sum + amountCents, 0),
      donations.reduce((sum, { data }) => sum + data.amountCents, 0))
    for (const entry of fund.data.entries) {
      assert.equal(entry.kind, 'contribution')
      assert.ok(donations.some(({ data }) => data.id === entry.donationId && data.amountCents === entry.amountCents
        && data.organizationId === entry.organizationId))
    }
    assert.equal(fund.data.basketPriceCents, basketPriceCents)
    const sponsors = seed.sponsorships.filter(({ data }) => data.id === fund.groupId).map(({ data }) => data.organizationId)
    assert.deepEqual([...fund.data.sponsorOrganizationIds].sort(), sponsors.sort())
  }
})

test('plan : organisme neuf = création sans écraser ; organisme présent = profil seulement, membres conservés', () => {
  const seed = buildOrganizationSeed(groups)
  const fresh = planOrganizationWrites(seed, { organizations: new Set(), funds: new Set() }, docName)
  const created = fresh.filter(({ update }) => /\/organizations\/[^/]+$/.test(update.name))
  assert.equal(created.length, seed.organizations.length)
  for (const write of created) {
    assert.deepEqual(write.currentDocument, { exists: false })
    assert.ok('memberUserIds' in write.update.fields)
  }
  assert.equal(fresh.filter(({ update }) => update.name.includes(`/${directoryCollection}/`)).length, seed.organizations.length)

  const present = planOrganizationWrites(seed, {
    organizations: new Set(seed.organizations.map(({ id }) => id)),
    funds: new Set(seed.funds.map(({ groupId }) => groupId))
  }, docName)
  for (const write of present.filter(({ update }) => /\/organizations\/[^/]+$/.test(update.name))) {
    assert.ok(!write.updateMask!.fieldPaths.includes('memberUserIds'))
    assert.ok(write.updateMask!.fieldPaths.includes('photoUpdatedAt'))
  }
  const fundWrites = present.filter(({ update }) => update.name.endsWith('/solidarity/fund'))
  assert.equal(fundWrites.length, seed.funds.length)
  for (const write of fundWrites) {
    assert.deepEqual(write.updateMask, { fieldPaths: [] })
    assert.ok(write.updateTransforms!.some(({ fieldPath }) => fieldPath === 'entries'))
  }
})

test('rattachement : organizationId + rôle sur le profil, uid dans memberUserIds, jamais de création', () => {
  const [user, org] = planMemberWrites('uid-1', docName)
  assert.ok(user.update.name.endsWith('/users/uid-1'))
  assert.deepEqual(user.updateMask, { fieldPaths: ['organizationId'] })
  assert.deepEqual(user.update.fields.organizationId, { stringValue: organizationId })
  assert.deepEqual(user.currentDocument, { exists: true })
  assert.ok(org.update.name.endsWith(`/organizations/${organizationId}`))
  assert.deepEqual(org.updateTransforms![0].appendMissingElements.values, [{ stringValue: 'uid-1' }])
  assert.deepEqual(org.currentDocument, { exists: true })
})
