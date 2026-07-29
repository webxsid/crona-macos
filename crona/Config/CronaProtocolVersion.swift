//
//  CronaProtocolVersion.swift
//  crona
//
//  Created by Siddharth Mittal on 17/05/26.
//

import Foundation

struct CronaProtocolVersion: RawRepresentable, Codable, Equatable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let current = CronaProtocolVersion(rawValue: "1.1")

    var isCompatibleWithCurrent: Bool {
        rawValue == Self.current.rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
