//
//  crc.swift
//  SimbaBLE
//
//  Created by Alexey Chechetkin on 21.01.2018.
//  Copyright © 2018 Alexey Chechetkin. All rights reserved.
//

import Foundation

struct Crc
{
    private static let INITIAL_VALUE: UInt32 = 0xffffffff
    private static let CRC_TABLE: [UInt32] = [ 0x00000000, 0x04C11DB7, 0x09823B6E, 0x0D4326D9, 0x130476DC,
                                       0x17C56B6B, 0x1A864DB2, 0x1E475005, 0x2608EDB8, 0x22C9F00F,
                                       0x2F8AD6D6, 0x2B4BCB61, 0x350C9B64, 0x31CD86D3, 0x3C8EA00A, 0x384FBDBD ]
    
    
    private static func Crc32Fast(_ CrcInit : UInt32, _ Data : UInt32) -> UInt32 {
        var Crc = CrcInit ^ Data
        
        Crc = (Crc << 4) ^ CRC_TABLE[Int(Crc >> 28)]
        Crc = (Crc << 4) ^ CRC_TABLE[Int(Crc >> 28)]
        Crc = (Crc << 4) ^ CRC_TABLE[Int(Crc >> 28)]
        Crc = (Crc << 4) ^ CRC_TABLE[Int(Crc >> 28)]
        Crc = (Crc << 4) ^ CRC_TABLE[Int(Crc >> 28)]
        Crc = (Crc << 4) ^ CRC_TABLE[Int(Crc >> 28)]
        Crc = (Crc << 4) ^ CRC_TABLE[Int(Crc >> 28)]
        Crc = (Crc << 4) ^ CRC_TABLE[Int(Crc >> 28)]
        
        return Crc
    }
    
    static func upgrade(_ data: NSData) -> UInt32 {
        guard (data.length % 4) == 0  else {
            print("==> Crc32 error, update() - Data length for CRC should be 4 bytes aligned, \(data.length)")
            return 0
        }
    
        var value: UInt32 = 0
        var crcValue = INITIAL_VALUE
        
        for i in stride(from: 0, to: data.length, by: 4) {
            data.getBytes(&value, range: NSMakeRange(i, 4))
            crcValue = Crc32Fast(crcValue, value);
        }
        
        return crcValue
    }
    
}





