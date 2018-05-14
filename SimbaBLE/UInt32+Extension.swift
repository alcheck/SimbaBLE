//
//  UInt32+Extension.swift
//  SimbaBLE
//
//  Created by Alexey Chechetkin on 14/05/2018.
//  Copyright © 2018 Alexey Chechetkin. All rights reserved.
//

import Foundation

extension UInt32 {
    
    func beToLe() -> UInt32 {
        var res: UInt32 = 0
        res |= (self & 0x000000ff) << 24
        res |= (self & 0x0000ff00) << 8
        res |= (self & 0x00ff0000) >> 8
        res |= (self & 0xff000000) >> 24
        return res
    }
}
