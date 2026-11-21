// DemandMapDemoData.swift
// Jeu de démo enrichi pour les previews de V3 Carte de la demande : six quartiers de Montréal
// au lieu de la seule commande de Saint-Michel de `FakeData.montreal`. Previews seulement (DEBUG).

#if DEBUG
import Foundation

extension FakeData {
    /// `FakeData.montreal` + cinq groupes publics avec des commandes groupées vivantes (riz, pommes, pommes de terre).
    static let demandMapDemo: FakeData = {
        var data = FakeData.montreal

        func group(_ id: String, _ name: String, _ neighborhood: String, _ geohash: String, households: Int) -> NeighborhoodGroup {
            NeighborhoodGroup(id: id, name: name, neighborhood: neighborhood, centerGeohash: geohash, radiusMeters: 900,
                              coordinatorIds: [], householdCount: households, isPublic: true, inviteCode: "")
        }

        func order(_ group: String, _ offer: String, shares: Int, households: Int, status: GroupOrder.Status = .open) -> GroupOrder {
            GroupOrder(id: "order-\(group)-\(offer)", groupId: group, offerId: offer, status: status, currentTierIndex: nil,
                       committedShares: shares, committedHouseholds: households, pickupPointId: nil, pickupSlots: [])
        }

        data.groups += [
            group("group-parc-ex-ouest", "Parc-Ex Ouest", "Parc-Extension", "f25eh8", households: 31),
            group("group-villeray", "Villeray en commun", "Villeray", "f25ehg", households: 18),
            group("group-cdn", "Côte-des-Neiges solidaire", "Côte-des-Neiges", "f25dud", households: 15),
            group("group-plateau", "Plateau partage", "Plateau-Mont-Royal", "f25dvx", households: 9),
            group("group-rosemont", "Rosemont ensemble", "Rosemont", "f25eje", households: 12),
        ]
        data.groupOrders += [
            order("group-parc-ex-ouest", FakeData.ID.riceOffer, shares: 26, households: 24, status: .reached),
            order("group-parc-ex-ouest", FakeData.ID.appleOffer, shares: 9, households: 7),
            order("group-villeray", FakeData.ID.riceOffer, shares: 14, households: 14),
            order("group-cdn", FakeData.ID.potatoOffer, shares: 11, households: 11),
            order("group-plateau", FakeData.ID.appleOffer, shares: 5, households: 5),
            order("group-rosemont", FakeData.ID.riceOffer, shares: 8, households: 6),
        ]
        return data
    }()
}
#endif
