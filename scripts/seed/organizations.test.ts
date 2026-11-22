import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { test } from 'node:test'
import {
  basketCount, basketPriceCents, buildOrganizationSeed, demoDonations, organizationId, planMemberWrites,
  planOrganizationWrites, type GroupInfo
} from './organizations.ts'

const groups = JSON.parse(await readFile(new URL('./fixtures/groups.json', import.meta.url), 'utf8')) as GroupInfo[]
const docName = (path: string) => `projects/p/databases/(default)/documents/${path}`

test('les groupes de démo existent dans les fixtures', () => {
  const ids = new Set(groups.map(({ id }) => id))
  for (const { groupId } of demoDonations) assert.ok(ids.has(groupId), groupId)
})

test('dons : montants entiers positifs, dans les limites des règles, paniers et ménages cohérents', () => {
  const seed = buildOrganizationSeed(groups)
  assert.ok(seed.donations.length >= 3)
  for (const { data } of seed.donations) {
    assert.ok(Number.isInteger(data.amountCents) && data.amountCents >= 1 && data.amountCents <= 500_000)
    assert.ok(data.basketCount >= 0 && data.householdsReached >= 0 && data.householdsReached <= data.basketCount)
    assert.equal(data.organizationId, organizationId)
    assert.equal(data.isSimulated, true)
    assert.equal(data.basketCount, basketCount(data))
  }
})

test('chaque fonds : une contribution par don du groupe, solde = somme des dons, parrainage cohérent', () => {
  const seed = buildOrganizationSeed(groups)
  for (const fund of seed.funds) {
    const donations = seed.donations.filter(({ data }) => data.groupId === fund.groupId)
    assert.equal(fund.data.entries.length, donations.length)
    assert.equal(fund.data.entries.reduce((sum, { amountCents }) => sum + amountCents, 0),
      donations.reduce((sum, { data }) => sum + data.amountCents, 0))
    for (const entry of fund.data.entries) {
      assert.equal(entry.kind, 'contribution')
      assert.ok(donations.some(({ data }) => data.id === entry.donationId && data.amountCents === entry.amountCents))
    }
    assert.equal(fund.data.basketPriceCents, basketPriceCents)
    const sponsored = seed.sponsorships.some(({ data }) => data.id === fund.groupId)
    assert.deepEqual(fund.data.sponsorOrganizationIds, sponsored ? [organizationId] : [])
  }
})

test('plan : organisme neuf = création sans écraser ; organisme présent = profil seulement, membres conservés', () => {
  const seed = buildOrganizationSeed(groups)
  const fresh = planOrganizationWrites(seed, { organization: false, funds: new Set() }, docName)
  const created = fresh[0]
  assert.deepEqual(created.currentDocument, { exists: false })
  assert.ok('memberUserIds' in created.update.fields)

  const present = planOrganizationWrites(seed, { organization: true, funds: new Set(seed.funds.map(({ groupId }) => groupId)) }, docName)
  assert.ok(!present[0].updateMask!.fieldPaths.includes('memberUserIds'))
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
