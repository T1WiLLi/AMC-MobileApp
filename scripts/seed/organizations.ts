// Organisme de démo du portail Organismes (T-194) : une banque alimentaire de Côte-des-Neiges, ses dons, ses
// parrainages et le fonds de solidarité des trois groupes qu'elle finance. Même schéma que l'app
// (`Organization.swift`, `FirestoreOrganizationRepository`) :
//   organizations/{orgId}                          profil + memberUserIds
//   organizations/{orgId}/donations/{donationId}   don simulé (montants entiers, en cents)
//   organizations/{orgId}/sponsorships/{groupId}   parrainage
//   groups/{groupId}/solidarity/fund               { entries, subsidizedHouseholds, basketPriceCents, sponsorOrganizationIds }
// Dates fixes (pas relatives à aujourd'hui) : relancer le seed est idempotent.
import { toRestFields, type RestFields, type RestWrite } from './firestoreRest.ts'

export const organizationId = 'org-banque-alimentaire-cdn'
export const basketPriceCents = 2_600

export type GroupInfo = { id: string, name: string, neighborhood: string, centerGeohash: string }

type DonationSeed = {
  id: string, groupId: string, kind: 'fund' | 'suspendedBaskets', amountCents: number
  householdsReached: number, date: Date
}
type SponsorshipSeed = { groupId: string, monthlyBasketGoal: number, startedAt: Date }
type FundSeed = { groupId: string, subsidizedHouseholds: number }

const date = (iso: string) => new Date(`${iso}T15:00:00Z`)

// Montants : un panier = 26 $. « fund » : le don libre paie floor(montant / 2600) paniers entiers.
export const demoDonations: DonationSeed[] = [
  { id: 'don-cdn-2026-09', groupId: 'group-cote-des-neiges', kind: 'suspendedBaskets', amountCents: 26_000, householdsReached: 10, date: date('2026-09-05') },
  { id: 'don-cdn-2026-10', groupId: 'group-cote-des-neiges', kind: 'fund', amountCents: 15_600, householdsReached: 2, date: date('2026-10-03') },
  { id: 'don-parc-ex-2026-10', groupId: 'group-parc-extension', kind: 'fund', amountCents: 10_400, householdsReached: 4, date: date('2026-10-10') },
  { id: 'don-parc-ex-2026-11', groupId: 'group-parc-extension', kind: 'suspendedBaskets', amountCents: 13_000, householdsReached: 3, date: date('2026-11-02') },
  { id: 'don-rosemont-2026-11', groupId: 'group-rosemont', kind: 'fund', amountCents: 5_200, householdsReached: 2, date: date('2026-11-09') }
]
export const demoSponsorships: SponsorshipSeed[] = [
  { groupId: 'group-cote-des-neiges', monthlyBasketGoal: 20, startedAt: date('2026-04-15') },
  { groupId: 'group-parc-extension', monthlyBasketGoal: 10, startedAt: date('2026-06-01') }
]
export const demoFunds: FundSeed[] = [
  { groupId: 'group-cote-des-neiges', subsidizedHouseholds: 12 },
  { groupId: 'group-parc-extension', subsidizedHouseholds: 8 },
  { groupId: 'group-rosemont', subsidizedHouseholds: 4 }
]

export function basketCount(donation: Pick<DonationSeed, 'kind' | 'amountCents'>): number {
  return Math.floor(donation.amountCents / basketPriceCents)
}

/** Documents de l'organisme de démo (valeurs JS : `Date` pour les timestamps). */
export function buildOrganizationSeed(groups: GroupInfo[]) {
  const byId = new Map(groups.map((group) => [group.id, group]))
  const group = (id: string) => {
    const found = byId.get(id)
    if (!found) throw new Error(`Groupe de démo introuvable : ${id}`)
    return found
  }
  const home = group('group-cote-des-neiges')
  const profile = {
    id: organizationId,
    name: 'Banque alimentaire de Côte-des-Neiges',
    kind: 'foodBank',
    neighborhood: home.neighborhood,
    geohash: home.centerGeohash,
    mission: 'Distribuer des paniers frais aux familles de Côte-des-Neiges et financer des paniers suspendus '
      + 'dans les groupes de quartier voisins.',
    createdAt: date('2026-03-01')
  }
  const donations = demoDonations.map((donation) => {
    const baskets = basketCount(donation)
    return {
      path: `organizations/${organizationId}/donations/${donation.id}`,
      data: {
        id: donation.id, organizationId, groupId: donation.groupId, groupName: group(donation.groupId).name,
        kind: donation.kind, amountCents: donation.amountCents, basketCount: baskets,
        householdsReached: Math.min(donation.householdsReached, baskets), date: donation.date, isSimulated: true
      }
    }
  })
  const sponsorships = demoSponsorships.map((sponsorship) => ({
    path: `organizations/${organizationId}/sponsorships/${sponsorship.groupId}`,
    data: {
      id: sponsorship.groupId, organizationId, groupName: group(sponsorship.groupId).name,
      neighborhood: group(sponsorship.groupId).neighborhood,
      monthlyBasketGoal: sponsorship.monthlyBasketGoal, startedAt: sponsorship.startedAt
    }
  }))
  const funds = demoFunds.map((fund) => ({
    groupId: fund.groupId,
    path: `groups/${fund.groupId}/solidarity/fund`,
    data: {
      // Une ligne par don, comme `FirestoreOrganizationRepository.donate` : la ligne nomme le don.
      entries: demoDonations.filter(({ groupId }) => groupId === fund.groupId).map((donation) => ({
        kind: 'contribution', amountCents: donation.amountCents, basketCount: 0, date: donation.date,
        donationId: donation.id, organizationId
      })),
      subsidizedHouseholds: fund.subsidizedHouseholds,
      basketPriceCents,
      sponsorOrganizationIds: demoSponsorships.some(({ groupId }) => groupId === fund.groupId) ? [organizationId] : []
    }
  }))
  return { profile, donations, sponsorships, funds }
}

export type Existing = { organization: boolean, funds: Set<string> }

/**
 * Écritures REST du seed. Rien n'est supprimé, et ce qui existe déjà est ménagé :
 *   - organisme présent : seuls les champs de profil sont réécrits (`memberUserIds` reste intact) ;
 *   - fonds présent : les lignes de démo et le parrainage sont ajoutés s'ils manquent (appendMissingElements),
 *     jamais de réécriture : le solde réel du groupe est conservé.
 */
export function planOrganizationWrites(
  seed: ReturnType<typeof buildOrganizationSeed>, existing: Existing, docName: (path: string) => string
): RestWrite[] {
  const writes: RestWrite[] = []
  const { createdAt, ...profileFields } = seed.profile
  const profilePath = `organizations/${organizationId}`
  writes.push(existing.organization
    ? {
        update: { name: docName(profilePath), fields: toRestFields({ ...profileFields, createdAt }) },
        updateMask: { fieldPaths: Object.keys({ ...profileFields, createdAt }) },
        currentDocument: { exists: true }
      }
    : { update: { name: docName(profilePath), fields: toRestFields({ ...seed.profile, memberUserIds: [] }) }, currentDocument: { exists: false } })
  for (const { path, data } of [...seed.donations, ...seed.sponsorships]) {
    writes.push({ update: { name: docName(path), fields: toRestFields(data) } })
  }
  for (const fund of seed.funds) {
    if (!existing.funds.has(fund.groupId)) {
      writes.push({ update: { name: docName(fund.path), fields: toRestFields(fund.data) }, currentDocument: { exists: false } })
      continue
    }
    const values = (list: unknown[]) => (toRestFields({ list }).list as { arrayValue: { values: Record<string, unknown>[] } }).arrayValue.values
    writes.push({
      update: { name: docName(fund.path), fields: {} as RestFields },
      updateMask: { fieldPaths: [] },
      updateTransforms: [
        { fieldPath: 'entries', appendMissingElements: { values: values(fund.data.entries) } },
        ...(fund.data.sponsorOrganizationIds.length === 0 ? [] : [
          { fieldPath: 'sponsorOrganizationIds', appendMissingElements: { values: values(fund.data.sponsorOrganizationIds) } }
        ])
      ],
      currentDocument: { exists: true }
    })
  }
  return writes
}

export function describeSeed(seed: ReturnType<typeof buildOrganizationSeed>): string[] {
  const cents = (value: number) => `${(value / 100).toFixed(2)} $`
  return [
    `Organisme : ${seed.profile.name} (${organizationId})`,
    `Dons : ${seed.donations.length} (${cents(demoDonations.reduce((sum, { amountCents }) => sum + amountCents, 0))})`,
    `Parrainages : ${seed.sponsorships.length}`,
    ...seed.funds.map((fund) =>
      `Fonds ${fund.groupId} : ${fund.data.entries.length} contribution(s), ` +
      `${cents(fund.data.entries.reduce((sum, { amountCents }) => sum + amountCents, 0))}, ` +
      `${fund.data.subsidizedHouseholds} ménage(s) aidé(s)`)
  ]
}

/** Écritures du rattachement d'un compte : `users/{uid}.organizationId` + rôle, et l'uid dans `memberUserIds`. */
export function planMemberWrites(uid: string, docName: (path: string) => string): RestWrite[] {
  return [
    {
      update: { name: docName(`users/${uid}`), fields: toRestFields({ organizationId }) },
      updateMask: { fieldPaths: ['organizationId'] },
      updateTransforms: [{ fieldPath: 'roles', appendMissingElements: { values: [{ stringValue: 'organization' }] } }],
      currentDocument: { exists: true }
    },
    {
      update: { name: docName(`organizations/${organizationId}`), fields: {} },
      updateMask: { fieldPaths: [] },
      updateTransforms: [{ fieldPath: 'memberUserIds', appendMissingElements: { values: [{ stringValue: uid }] } }],
      currentDocument: { exists: true }
    }
  ]
}
