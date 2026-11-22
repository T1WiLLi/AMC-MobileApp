import Testing
@testable import AMC_MobileApp

/// FB-08 : chaque bouton « i » a quelque chose à dire.
struct InfoTopicTests {
    @Test(arguments: InfoTopic.allCases)
    func everyTopicHasATitleAndAMessage(topic: InfoTopic) {
        #expect(!topic.title.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(!topic.message.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(!topic.systemImage.isEmpty)
    }

    @Test(arguments: InfoTopic.allCases)
    func messageStaysShort(topic: InfoTopic) {
        // 2-3 phrases simples : une fenêtre compacte, pas un article.
        let sentences = topic.message.split(whereSeparator: { ".!?".contains($0) }).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect((1...3).contains(sentences.count))
    }

    @Test(arguments: InfoTopic.allCases)
    func voiceOverLabelNamesTheTopic(topic: InfoTopic) {
        #expect(topic.accessibilityLabel.hasPrefix("En savoir plus sur "))
        #expect(topic.accessibilityLabel.count > "En savoir plus sur ".count)
    }

    @Test func idsAreUnique() {
        #expect(Set(InfoTopic.allCases.map(\.id)).count == InfoTopic.allCases.count)
    }
}
