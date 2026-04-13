import Foundation

enum FrameCoachingProfile: String, CaseIterable, Identifiable {
    case singleDeskSpeaker
    case twoPersonPodcast
    case verticalSocialVideo
    case verticalConversation
    case screenGuide

    var id: String { rawValue }

    var label: String {
        switch self {
        case .singleDeskSpeaker:
            return String(localized: "Tek Kişi Masabaşı")
        case .twoPersonPodcast:
            return String(localized: "İki Kişi Podcast")
        case .verticalSocialVideo:
            return String(localized: "Dikey Sosyal Video")
        case .verticalConversation:
            return String(localized: "Dikey Sohbet")
        case .screenGuide:
            return String(localized: "Ekran Anlatımı")
        }
    }
}
