import Foundation

enum BrandTagline {
    static let options = [
        "Motion. Media. Modular.",
        "Your Streams, Your Modules, Your Rules.",
        "Fluid streaming, limitless extensions."
    ]
}

enum TaglineSelector {
    static func next(
        previous: String?,
        candidates: [String] = BrandTagline.options,
        choose: ([String]) -> String? = { $0.randomElement() }
    ) -> String {
        guard !candidates.isEmpty else {
            return BrandTagline.options[0]
        }

        let eligible = candidates.count > 1
            ? candidates.filter { $0 != previous }
            : candidates

        return choose(eligible) ?? eligible[0]
    }
}
