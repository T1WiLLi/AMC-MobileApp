import assert from 'node:assert/strict'
import { test } from 'node:test'
import { ownerOf, planBackfill, type Household, type Member } from './backfillMemberUserId.ts'

const member = (householdId: string, userId: string | null = null): Member =>
  ({ path: `groups/g/members/${householdId}`, groupId: 'g', householdId, userId })

test('le propriétaire est ownerId, sinon le premier compte du ménage', () => {
  assert.equal(ownerOf({ ownerId: 'b', userIds: ['a', 'b'] }), 'b')
  assert.equal(ownerOf({ ownerId: null, userIds: ['a', 'b'] }), 'a')
  assert.equal(ownerOf({ ownerId: null, userIds: [] }), null)
})

test('plan : met à jour seulement les adhésions sans userId, explique les autres', () => {
  const households = new Map<string, Household>([
    ['h1', { ownerId: 'u1', userIds: ['u1', 'u9'] }],
    ['h2', { ownerId: null, userIds: ['u2'] }],
    ['h3', { ownerId: null, userIds: [] }]
  ])
  const plan = planBackfill([member('h1'), member('h2'), member('h3'), member('h4'), member('h1', 'deja')], households)
  assert.deepEqual(plan.updates, [
    { path: 'groups/g/members/h1', userId: 'u1' },
    { path: 'groups/g/members/h2', userId: 'u2' }
  ])
  assert.deepEqual(plan.skipped.map(({ reason }) => reason), ['menage-sans-compte', 'menage-introuvable', 'deja-renseigne'])
})

test('idempotent : relancer le plan après écriture ne change plus rien', () => {
  const households = new Map<string, Household>([['h1', { ownerId: 'u1', userIds: ['u1'] }]])
  const second = planBackfill([member('h1', 'u1')], households)
  assert.equal(second.updates.length, 0)
})
