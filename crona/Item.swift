//
//  Item.swift
//  crona
//
//  Created by Siddharth Mittal on 16/05/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
