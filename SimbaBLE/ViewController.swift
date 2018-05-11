//
//  ViewController.swift
//  SimbaBLE
//
//  Created by Alexey Chechetkin on 20/12/2017.
//  Copyright © 2017 Alexey Chechetkin. All rights reserved.
//

import UIKit
import CoreBluetooth

class ViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate
{
    var centralManager: CBCentralManager?
    var initialized = false
    var peripheral: CBPeripheral?
    
    // MARK: - Debug service characteristic UUIDs
    let charDebugErrorUUID  =  CBUUID(string:"00000002-000E-11E1-AC36-0002A5D5C51B") // read only
    let charDebugTermUUID   =  CBUUID(string:"00000001-000E-11E1-AC36-0002A5D5C51B") // read, write, notify
    
    // holds debug terminal characteristic
    var termChar: CBCharacteristic?
    // holds debug error terminal characteristic
    var errChar: CBCharacteristic?
    
    // out message
    var stdOutMsg: String = ""
    
    // fw process send initial command
    var fwStarted = false
    
    // fw started to send fw to the device
    var fwUploadInProgress = false
    
    // stored for initial ack
    var fwCrc: UInt32 = 0
    
    // bytes sended
    var fwBytesSended: UInt32 = 0
    
    // packages sent
    var fwPackageSended = 0
    
    // return firmware Data
    func fwData(_ firmwareName:String) -> NSData {
        let url = Bundle.main.url(forResource: firmwareName , withExtension: "bin")
        return NSData(contentsOf: url!)!
    }
    
    // holds the copy of firmware data
    // during firmware update process
    var fwContent = NSData()
    
    // available firmwares
    let fwFiles = [ 1000 : "SensiBLE_SIMBA_ota", 1001 : "fw1", 1002 : "fw2", 1003 : "fw3"]
    
    // MARK: - Common service characterstic UUIDs for SymbaPRO
    let charLuminosityUUID  =  CBUUID(string:"01000000-0001-11E1-AC36-0002A5D5C51B") // uint16
    let charMicLevelUUID    =  CBUUID(string:"04000000-0001-11E1-AC36-0002A5D5C51B") // uint8, mic1, mic2 db
    let charTempUUID        =  CBUUID(string:"00040000-0001-11E1-AC36-0002A5D5C51B") // uint16 * 10
    let charHumidityUUID    =  CBUUID(string:"00080000-0001-11E1-AC36-0002A5D5C51B") // int16 * 10
    let charPressureUUID    =  CBUUID(string:"00100000-0001-11E1-AC36-0002A5D5C51B") // int32 * 100
    let charBeamFormingUUID =  CBUUID(string:"00020000-0001-11E1-AC36-0002A5D5C51B") // - uint8
    let charMovementUUID    =  CBUUID(string:"00E00000-0001-11E1-AC36-0002A5D5C51B") // acc, gyro * 10, mag
    let charEnvironmentUUID =  CBUUID(string:"001C0000-0001-11E1-AC36-0002A5D5C51B") // pressure, humidity, temperature
    
    // MARK: - Common service chars UUID for OnSemi RSL10
    let onSemiCharLuxUUID = CBUUID(string: "E093F3B5-00A3-A9E5-9ECA-40036E0EDC24")  // Luminosity uint32 * 1000 - 4 bytes, lx
    let onSemiCharPirUUID = CBUUID(string: "E093F3B5-00A3-A9E5-9ECA-40046E0EDC24")  // Movement detector - 1 bytes
    
    // MARK: - UI outlets
    @IBOutlet weak var msgLabel: UILabel!
    @IBOutlet weak var macAddressLabel: UILabel!
    @IBOutlet weak var fwFlashLabel: UILabel!
    @IBOutlet weak var fwVersionLabel: UILabel!
    @IBOutlet weak var fwProgressBar: UIProgressView!
    
    // update status message
    var msg: String? {
        didSet {
            msgLabel.text = msg
        }
    }
    
    // MARK: - Common
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        centralManager = CBCentralManager(delegate: self, queue: nil);
    }

    // MARK: CBCentralDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    {
        switch central.state {
        case .poweredOn:
            msg = "Powered On, start scan for peripherals ..."
            central.scanForPeripherals(withServices: nil, options: nil)
            
        default:
            msg = "Not powered On, try to enable Bluetooth and start again"
            break
        }
    }
    
    // found device
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber)
    {
        //msg = "Discovered peripheral - \(peripheral.name ?? "Unknown"), uuid:\(peripheral.identifier)"
        
        if let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            print("CentralManager() -> Advertisment name: \(advName)")
        }
        
        if let rawData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            print("CentralManager() -> \(peripheral.name ?? "Unknown") Manufacturer data: \(rawData.count)")
            if rawData.count == 12 {
                let address = String(format: "%02x:%02x:%02x:%02x:%02x:%02x", rawData[6], rawData[7], rawData[8], rawData[9], rawData[10], rawData[11])
                
                print("CentralManager() -> MAC address: \(address)")
                macAddressLabel.text = "MAC address: \(address)"
                
                if !address.hasSuffix(":52:31") {
                    print("CentralManager() -> this MAC address is not our device's")
                    return
                }
            }
            else if rawData.count == 10 {
                // the standard implementation has only 4 bytes of product id
                // the custom implementation adds 6 bytes to that - this is mac address
                // first 4 symbols should be 62:03:03:03
                // big endian order
                let address = String(format:"%02x:%02x:%02x:%02x:%02x:%02x", rawData[9], rawData[8], rawData[7], rawData[6], rawData[5], rawData[4])
                
                print("CentralManager() -> \(peripheral.name ?? "") MAC address: \(address)")
            }
        }

        guard let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
//                  name.hasPrefix("SIM-BS1") ||
//                  name.hasPrefix("SensiBLE") ||
//                  name.hasPrefix("SensBLE") ||
                  name.hasPrefix("Arrow_")
        else {
            return
        }
        
        msg = "Connecting to \(name)..."
        
        self.peripheral = peripheral
        central.connect(peripheral, options: nil)
    }
    
    // connected to the device
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    {
        print("CentralManager() -> Successfully connected to \(peripheral.name ?? "Unknown")")
        msg = "Discovering services ..."
        
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        if let err = error {
            print("==> Disconect with device with Error: \(err.localizedDescription)")
        }
        
        print("==> Disconnected with device")
        self.peripheral = nil
        
        macAddressLabel.text = ""
        fwVersionLabel.text = ""
        msg = "Disconnected"
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)
    {
        msg = "Failed to connect tor the peripheral"
        macAddressLabel.text = ""
        fwVersionLabel.text = ""
        
        if let err = error {
            print("==> Failed to connect to the device: \(err.localizedDescription)")
        }
    }
    
    // MARK: CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    {
        guard let services = peripheral.services else {
            print("Peripheral() -> Service list is nil, return")
            msg = "Service list is empty"
            return
        }
        
        if let err = error {
            print("Peripheral() -> Error discovering services: \(err.localizedDescription)")
            msg = err.localizedDescription
            return
        }
        
        print("Peripheral() -> Services discovered, discovering chars...")
        
        for srv in services {
            //print("Peripheral() -> Discover chars for service \(srv.uuid)")
            peripheral.discoverCharacteristics(nil, for: srv)
        }
        
        msg = "Discovering characteristics..."
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    {
        guard error == nil, let chars = service.characteristics else {
            print("Peripheral() -> Discover chars for service \(service.uuid) - \(error?.localizedDescription ?? "")")
            return
        }
        
        print("Peripheral() -> Found chars for service \(service.uuid)")
        
        for char in chars {
            
            // save debug chars
            switch char.uuid {
                case charDebugTermUUID:
                    peripheral.setNotifyValue(true, for: char)
                    termChar = char
                
                case charDebugErrorUUID:
                    peripheral.setNotifyValue(true, for: char)
                    errChar = char
                
                default:
                    break
            }
            
            var props = ""
            
            if char.properties.contains(.read) {
                props += "-read"
                //peripheral.readValue(for: char)
            }
            
            if char.properties.contains(.write) {
                props += "-write"
            }
            
            if char.properties.contains(.notify) {
                props += "-notify"
                let uuid = char.uuid
                
                // subscribe to notification for OnSemi BLE
                if uuid == onSemiCharPirUUID {
                    print("Peripheral() -> Subscribed to char: \(uuid)")
                    peripheral.setNotifyValue(true, for: char)
                }
                else if uuid == onSemiCharLuxUUID {
                    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                        peripheral.readValue(for: char)
                    }
                }
            }
            
//            if char.properties.contains(.notify) &&
//                (char.uuid == charMovementUUID || char.uuid == charBeamFormingUUID)
//            {
//                props += "notify | "
//                peripheral.setNotifyValue(true, for: char)
//            }
            
            if char.properties.contains(.broadcast) {
                props += "-broadcast"
            }
            
            if char.properties.contains(.writeWithoutResponse) {
                props += "-write[w/o response]"
            }
            
            print("Peripheral() -> Char \(char.uuid) props: \(props)")
        }
    }
    
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    {
        guard error == nil, let data = characteristic.value else {
            print("Peripheral() -> \(error!.localizedDescription)")
            return
        }
        
        //let ts = uint16fromData(data)

        switch characteristic.uuid
        {
        case charDebugTermUUID:
            debugStdOutReceived(data)
            
        case charDebugErrorUUID:
            debugErrDataReceived(data)
            
//        case charEnvironmentUUID:
//            //print("env set: data length = \(data.count)")
//            let press = Double( int32fromData(data, offset: 2) ) * 0.01
//            let hum = Double(uint16fromData(data, offset: 6)) * 0.1
//            let t = Double( uint16fromData(data, offset: 8) ) * 0.1
//            print("env pressure: \(press) mBar, humidity:\(hum)%, temp:\(t) C")
//
//        case charTempUUID:
//            // int16 * 10
//            let t = Double( uint16fromData(data, offset: 2) ) / 10.0
//            print("temp len:\(data.count), temp:\(t) C")
//
//        case charLuminosityUUID:
//            let l = Double( uint16fromData(data, offset: 2) )
//            print("luminosity len:\(data.count), lum:\(l) lux")
//
//        case charMicLevelUUID:
//            let mic1 = uint8fromData(data, offset: 2)
//            let mic2 = uint8fromData(data, offset: 3)
//            print("miclevel len:\(data.count), mic1:\(mic1) db, mic2:\(mic2) db")
//
//        case charHumidityUUID:
//            let hum = Double(uint16fromData(data, offset: 2))/10.0
//            print("humidity len:\(data.count), humidity:\(hum)%")
//
//        case charPressureUUID:
//            let press = Double( int32fromData(data, offset: 2) ) / 100.0
//            print("pressure len:\(data.count), press:\(press) mBar")
            
//        case charBeamFormingUUID:
//            let x = Double( int16fromData(data, offset: 3) )
//            let y = Double( int16fromData(data, offset: 5) )
//            let z = Double( int16fromData(data, offset: 7) )
//            let dir = uint8fromData(data, offset: 2)
//            print("beam forming len:\(data.count), direction: \(dir), (\(x), \(y), \(z))")
        
//        case charMovementUUID:
//            let xAcc = int16fromData(data, offset: 2)
//            let yAcc = int16fromData(data, offset: 4)
//            let zAcc = int16fromData(data, offset: 6)
//
//            let xGyro = Double( int16fromData(data, offset: 8) ) / 10.0
//            let yGyro = Double( int16fromData(data, offset: 10) ) / 10.0
//            let zGyro = Double( int16fromData(data, offset: 12) ) / 10.0
//
//            let xMag = int16fromData(data, offset: 14)
//            let yMag = int16fromData(data, offset: 16)
//            let zMag = int16fromData(data, offset: 18)
//
//            print("movement len:\(data.count), acc:(\(xAcc),\(yAcc),\(zAcc)), gyro:(\(xGyro),\(yGyro),\(zGyro)), mag:(\(xMag),\(yMag),\(zMag))")
            
        case onSemiCharLuxUUID:
            // print("Data length: \(data.count)")
            let lux = float32fromData(data)
            msg = "Luminosity: \(lux) lx"
            print(msg!)
            
        case onSemiCharPirUUID:
            let pirValue = uint8fromData(data)
            msg = "Pir: \(pirValue)"
            print(msg!)
            
        default:
            break
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == charDebugTermUUID {
            debugStdInSend(error)
        }
    }
    
    // MARK: - Debug chars handlers
    func sendFwPackage() -> Bool {
    
        let lastPackageSize: UInt32 = min( UInt32(fwContent.length) - fwBytesSended, 16 )
    
        // nothing to send any more
        if lastPackageSize == 0 {
            print("==> Last package size = 0, bytesSended = \(fwBytesSended)")
            return false
        }
        
        if (fwBytesSended + lastPackageSize) > fwContent.length {
            print("==> Nothing to send anymore, bytesSended = \(fwBytesSended)")
            return false
        }
        
        let dataPkg = fwContent.subdata(with: NSMakeRange(Int(fwBytesSended), Int(lastPackageSize)))
    
        fwBytesSended += lastPackageSize;
    
        if let device = peripheral, let term = termChar, device.state == .connected {
            device.writeValue(dataPkg, for: term, type: .withoutResponse )
            debugStdInSend(nil)
            
            return true;
        }
        else {
            print("==> SendPackageBlock() Error: Device is not connected, fw aborted")
            msg = "Can not send data, device/debug char is not available"
            return false
        }
    }
    
    
    func sendFwBlock() {
        DispatchQueue.main.asyncAfter(deadline: .now() + (1.0/90.0) ) {
            if self.sendFwPackage() {
                self.sendFwBlock()
            }
            else {
                print("==> SendFwExited to send block, bytesSended = \(self.fwBytesSended)")
            }
        }
    }
    
    // on characteristic update
    func debugStdOutReceived(_ data: Data) {
        
        // fw progress block
        if fwStarted {
            
            if fwUploadInProgress {
                // waiting ACK for fw complete

                if data.count >= 1 && data[0] == 0x1  {
                    print("==> Fw complete ACK message received")
                    
                    fwFlashLabel.text = "Upgrade completed, waiting to reboot"
                    msg = "Firmware Updated Successfully"
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: {
                        self.reconnectButtonPressed(UIButton())
                    })
                }
                else if let msg = NSString(data: data, encoding: 5) {
                    print("==> StdOut message in Fw process: \(msg)")
                }
                
                fwStarted = false
                fwUploadInProgress = false
            }
            else {
                // should receive start fw ACK message with crc
                var crc: UInt32 = 0
                let nsdata = data as NSData
                
                nsdata.getBytes(&crc, length: 4)
                
                if crc == fwCrc {
                    print("==> Crc checked OK, can start upload FW")
                    msg = "Updating firmware..."
                    
                    fwBytesSended = 0
                    fwPackageSended = 0
                    fwUploadInProgress = true
                    
                    // start to send blocks
                    sendFwBlock()
                }
                else {
                    msg = "Update abortet, got wrong CRC code"
                    print("==> Wrong Crc retrieved from device")
                    fwStarted = false
                }
            }
        }
        // basically it is fw version reading block
        else if let msg = NSString(data: data, encoding: 5) {
            
            stdOutMsg += msg as String
            
            // \r\n means end of the output message sequence
            if msg.hasSuffix("\r\n") {
                print("==> Debug out message: \(stdOutMsg)")
                
                let fwRegExp = try! NSRegularExpression(pattern: "(.*)_(.*)_(\\d+)\\.(\\d+)\\.(\\d+)", options: .anchorsMatchLines)
                
                let matches = fwRegExp.matches(in: stdOutMsg, options: .anchored, range: NSMakeRange(0, stdOutMsg.count))
                
                if matches.count > 0 {
                    print("==> Firmware output detected")
                    
                    fwVersionLabel.text = stdOutMsg
                    
                    for match in matches {
                        if match.numberOfRanges != 6 {
                            continue
                        }
                        
                        let typeRange = match.range(at: 1)
                        let nameRage =  match.range(at: 2)
                        let majoirRange = match.range(at: 3)
                        let minorRange =  match.range(at: 4)
                        let patchRange =  match.range(at: 5)
                        
                        let s = stdOutMsg as NSString
                        
                        let name = s.substring(with: nameRage)
                        let mcuType = s.substring(with: typeRange)
                        let majoir = Int(s.substring(with: majoirRange))!
                        let minor = Int(s.substring(with: minorRange))!
                        let patch = Int(s.substring(with: patchRange))!
                        
                        print("==> Name: \(name), mcu: \(mcuType), major:\(majoir), minor:\(minor), patch:\(patch)")
                    }
                }
                else {
                    self.msg = msg as String
                }
            }
        }
    }
    
    // on characteristic write
    func debugStdInSend(_ error:Error?) {
        if let error = error {
            print("==> StdIn Error: \(error.localizedDescription)")
            return
        }
        
        if fwUploadInProgress {
            fwPackageSended += 1
            if ( fwPackageSended % 10 ) == 0 {
                let progress = Float(fwBytesSended) / Float(fwContent.length)
                fwFlashLabel.text = "Flashed \(fwBytesSended) / \(fwContent.length)"
                fwProgressBar.setProgress(progress, animated: true)
            }
        }
        else {
            print("==> StdInSend")
        }
    }
    
    func debugErrDataReceived(_ data: Data) {
        if let msg = NSString(data: data, encoding: 5) {
            print("==> StdErrorOut: \(msg)")
        }
    }
    
    // MARK: - UI handlers
    
    @IBAction func buttonGetFwPressed(_ sender: UIButton) {
        
        fwVersionLabel.text = ""
        
        guard let termChar = termChar else {
            msg = "Debug char is not available"
            return
        }
        
        stdOutMsg = ""
        let getFwCmd = "versionFw\r\n" as NSString
        let data = getFwCmd.data(using: 5) // ISOLatinEncoding
        
        if let device = peripheral, device.state == .connected {
            device.writeValue(data!, for: termChar, type: .withResponse )
        }
        else {
            print("==> Error: Device is not connected")
        }
    }
    
    @IBAction func reconnectButtonPressed(_ sender: UIButton) {
        if let manager = centralManager {
//            manager.scanForPeripherals(withServices: [CBUUID(string:"00000000-0001-11E1-9AB4-0002A5D5C51B"),
//                                                      CBUUID(string:"00000000-000E-11E1-9AB4-0002A5D5C51B"),
//                                                      CBUUID(string:"00000000-000F-11E1-9AB4-0002A5D5C51B")],
//                                       options: nil)
            manager.scanForPeripherals(withServices: nil, options: nil)
            
            peripheral = nil
            fwUploadInProgress = false
            fwStarted = false
        }
        else {
            print("==> CentralManager is nil, can not rediscover/reconnect")
        }
    }
    
    
    @IBAction func updateFwButtonPressed(_ sender: UIButton) {
        let tag = sender.tag
        
        if let fwName = fwFiles[tag] {
            let data = fwData(fwName)
            print("==> Start updating firmware: \(fwName), length: \(data.length)")
            startUpdateFw(data)
        }
        else {
            print("==> Can not get firmware file")
        }
    }
    
    func startUpdateFw(_ data: NSData) {
        
        guard let termChar = termChar, fwStarted == false else {
            msg = "Debug char is not available"
            return
        }
        
        // save for sending process
        fwContent = data
        
        let length = fwContent.length - (fwContent.length % 4)
        let tmpData = NSData(bytes: fwContent.bytes, length: length)
        var crc = Crc.upgrade(tmpData)
        
        fwCrc = crc // save to check later
        
        if crc == 0 {
            print("==> Wrong CRC calculated, abord fw upgrade")
            return
        }
        
        var fwLength: UInt32 = UInt32( fwContent.length )
        
        let cmd = "upgradeFw" as NSString
        let cmdData = cmd.data(using: 5)!
        
        let mData = NSMutableData(data: cmdData)
        mData.append(&fwLength, length: 4)
        mData.append(&crc, length: 4)
        
        print( String(format:"==> Crc: 0x%0x, dataLength: \(fwContent.length)", crc) )
        
        print("==> Sending upgradeFw command")
        
        fwStarted = true
        
        fwProgressBar.setProgress(0, animated: false)
        
        peripheral!.writeValue(mData as Data, for: termChar, type: .withResponse)        
    }
    
    // MARK: - Helpers
    
    func uint16fromData( _ data:Data, offset:Int = 0 ) -> UInt16
    {
        var t: UInt16 = 0
        let nsdata = data as NSData
        nsdata.getBytes(&t, range: NSMakeRange(offset, 2))
        return t
    }
    
    func int16fromData( _ data:Data, offset:Int = 0 ) -> Int16
    {
        var t: Int16 = 0
        let nsdata = data as NSData
        nsdata.getBytes(&t, range: NSMakeRange(offset, 2))
        return t
    }
    
    func uint8fromData( _ data:Data, offset:Int = 0 ) -> UInt8
    {
        var t: UInt8 = 0
        let nsdata = data as NSData
        nsdata.getBytes(&t, range: NSMakeRange(offset, 1))
        return t
    }

    func int32fromData( _ data:Data, offset:Int = 0 ) -> Int32
    {
        var t: Int32 = 0
        let nsdata = data as NSData
        nsdata.getBytes(&t, range: NSMakeRange(offset, 4))
        return t
    }
    
    func uint32fromData(_ data: Data, offset: Int = 0 ) -> UInt32
    {
        var t: UInt32 = 0
        let nsdata = data as NSData
        nsdata.getBytes(&t, range: NSMakeRange(offset, 4))
        return t
    }
    
    func float32fromData(_ data: Data, offset: Int = 0) -> Float
    {
        return Float(bitPattern: UInt32(bigEndian: data.withUnsafeBytes{ $0.pointee }))
    }
}

