//
//  Data+Extension.swift
//  SimbaBLE
//
//  Created by Alexey Chechetkin on 14/05/2018.
//  Copyright © 2018 Alexey Chechetkin. All rights reserved.
//

import Foundation

extension Data {
    // MARK: - Helpers
    
    func uint16(offset:Int = 0) -> UInt16
    {
        var t: UInt16 = 0
        let nsdata = self as NSData
        nsdata.getBytes(&t, range: NSMakeRange(offset, 2))
        return t
    }
    
    func int16(offset:Int = 0) -> Int16
    {
        var t: Int16 = 0
        let nsdata = self as NSData
        nsdata.getBytes(&t, range: NSMakeRange(offset, 2))
        return t
    }
    
    func uint8(offset:Int = 0) -> UInt8
    {
        var t: UInt8 = 0
        let nsdata = self as NSData
        nsdata.getBytes(&t, range: NSMakeRange(offset, 1))
        return t
    }
    
    func int8(offset:Int = 0) -> Int8
    {
        var t: Int8 = 0
        let nsdata = self as NSData
        nsdata.getBytes(&t, range: NSMakeRange(offset, 1))
        return t
    }
    
    func int32(offset:Int = 0) -> Int32
    {
        var t: Int32 = 0
        let nsdata = self as NSData
        nsdata.getBytes(&t, range: NSMakeRange(offset, 4))
        return t
    }
    
    func uint32(offset:Int = 0) -> UInt32
    {
        var t: UInt32 = 0
        let nsdata = self as NSData
        nsdata.getBytes(&t, range: NSMakeRange(offset, 4))
        return t
    }
}


