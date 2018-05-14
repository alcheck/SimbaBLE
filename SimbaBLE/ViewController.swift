//
//  ViewController.swift
//  SimbaBLE
//
//  Created by Alexey Chechetkin on 20/12/2017.
//  Copyright © 2017 Alexey Chechetkin. All rights reserved.
//

import UIKit
import CoreBluetooth

class ViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate, UITableViewDelegate, UITableViewDataSource
{
    var centralManager: CBCentralManager?
    var initialized = false
    var peripheral: CBPeripheral?
    
    // MAR: - Debug service characteristic UUIDs
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
    
    // blueST advertisment packet
    struct STAdvPacket {
        // holds data
        private var data: Data
        
        init(_ data: Data) {
            self.data = data
        }
        
        var isSTPacket: Bool {
            return (data.count == 6 || data.count == 12) && protocolVer >= 1 // compact or full size packet
        }
        
        var protocolVer: Int {
            return Int(data[0])
        }
        
        var deviceType: Int {
            return Int(data[1])
        }
        
        var macAddress: String? {
            guard data.count == 12 else {
                return nil
            }
            
            return String(format: "%02x:%02x:%02x:%02x:%02x:%02x", data[6], data[7], data[8], data[9], data[10], data[11])
        }
    }
    
    // blueST common feature, ref type
    class STFeature {
        // common service should ends with this suffix
        static let serviceSuffixUUID = "-0001-11E1-9AB4-0002A5D5C51B"
        
        // blueST feature value type
        enum FeatureType: Int {
            case int8,  uint8
            case int16, uint16, int16x3, int16x4
            case int32, uint32
            
            var size: Int {
                switch self {
                case .int8, .uint8:
                    return 1
                case .int16, .uint16:
                    return 2
                case .int32, .uint32:
                    return 4
                case .int16x3:
                    return 6
                case .int16x4:
                    return 8
                }
            }
        }
        
        var name: String
        var unit: String
        var type: FeatureType
        var scale: Float
        var translation: ((Float) -> Float)?
        var offset: Int
        var lastValue: String   // holds last value
        
        init(_ name: String, unit: String, type: FeatureType, scale: Float = 1.0, translation: ((Float) -> Float)? = nil, offset: Int = 0) {
            self.name = name
            self.type = type
            self.unit = unit
            self.scale = scale
            self.translation = translation
            self.offset = offset
            self.lastValue = "-"
        }
        
        // process data and stores the value in the lastValue field
        func processData(_ data: Data) {
            switch type {
            case .int8:
                lastValue = "\(t(Float(data.int8(offset: offset))))"
                
            case .uint8:
                lastValue = "\(t(Float(data.uint8(offset: offset))))"

            case .int16:
                lastValue = "\(t(Float(data.int16(offset: offset))))"

            case .uint16:
                lastValue = "\(t(Float(data.uint16(offset: offset))))"

            case .int32:
                lastValue = "\(t(Float(data.int32(offset: offset))))"

            case .uint32:
                lastValue = "\(t(Float(data.uint32(offset: offset))))"                
            
            case .int16x3:
                let val0 = t(Float(data.int16(offset: offset)))
                let val1 = t(Float(data.int16(offset: offset + 2)))
                let val2 = t(Float(data.int16(offset: offset + 4)))
                lastValue = "X:\(val0)\r\nY:\(val1)\r\nZ:\(val2)"

            case .int16x4:
                lastValue = "int16x4"
            }
        }
        
        private func t(_ v: Float ) -> Float {
            var r = v * scale
            if let trans = translation { r = trans(r) }
            return r
        }
    }
    
    // compound ST sensor, holds array of ST
    // features and BL characteristic related to them
    class STSensor: CustomStringConvertible {
        
        var char: CBCharacteristic
        var features: [STFeature] = []
        
        init(char: CBCharacteristic) {
            self.char = char
        }
        
        func addFeature(_ feature: STFeature) {
            features.append(feature)
        }
        
        func processData(_ data: Data) {
            features.forEach{ $0.processData(data) }
        }
        
        func indexOf(_ feature: STFeature) -> Int? {
            return features.index(where: { $0 === feature })
        }
        
        var description: String {
            var res = "\r\n"
            for (i, f) in features.enumerated() {
                res += "[\(i)]: \(f.name), \(f.lastValue) \(f.unit)\r\n"
            }
            
            return res
        }
    }
    
    // blueST featureMap
    let featureMap: [UInt32: STFeature] = [
        0x40000000: STFeature( "Adpm sync",            unit: "-",    type: .uint32),
        0x20000000: STFeature( "Switch",               unit: "-",    type: .uint8),
        0x10000000: STFeature( "Direction of arrival", unit: "-",    type: .int16),
        0x08000000: STFeature( "Audio ADPCM",          unit: "-",    type: .int16),       // use full packet data size
        0x04000000: STFeature( "Mic Level",            unit: "db",   type: .uint8),
        0x02000000: STFeature( "Proximity",            unit: "mm",   type: .uint16),
        0x01000000: STFeature( "Luminosity",           unit: "lux",  type: .uint16),
        0x00800000: STFeature( "Accelerometer",        unit: "mg",   type: .int16x3),
        0x00400000: STFeature( "Gyroscope",            unit: "dps",  type: .int16x3, scale: 0.1),
        0x00200000: STFeature( "Magnetometer",         unit: "mGa",  type: .int16x3),
        0x00100000: STFeature( "Pressure",             unit: "mBar", type: .uint32,  scale: 0.01),
        0x00080000: STFeature( "Humidity",             unit: "%",    type: .int16,   scale: 0.1),
        0x00040000: STFeature( "Temperature",          unit: "F",    type: .int16,   scale: 0.1,  translation: { $0 * 1.8 + 32.0 }),
        0x00020000: STFeature( "Battery",              unit: "-",    type: .int16x4),
        0x00010000: STFeature( "Temperature 2",        unit: "F",    type: .int16,   scale: 0.1,  translation: { $0 * 1.8 + 32.0 })
    ]
    
    // detected features
    var sensors: [STSensor] = []
    
    // MARK: - UI outlets
    @IBOutlet weak var msgLabel: UILabel!
    @IBOutlet weak var macAddressLabel: UILabel!
    @IBOutlet weak var fwFlashLabel: UILabel!
    @IBOutlet weak var fwVersionLabel: UILabel!
    @IBOutlet weak var fwProgressBar: UIProgressView!
    @IBOutlet weak var tableView: UITableView!
    
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
        tableView.dataSource = self
        tableView.delegate = self
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
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            return
        }
        
        let stPacket = STAdvPacket(data)
        guard stPacket.isSTPacket else {
            //print("CentralManager() -> Not ST packet")
            return
        }
        
        if let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            print("CentralManager() -> Advertisment name: \(advName)")
        }
        
        print("CentralManager() -> Protocol version: \(stPacket.protocolVer)")
        print("CentralManager() -> Device type: \(stPacket.deviceType)")

        msg = "Connecting to \(peripheral.name ?? "-")..."
        
        self.peripheral = peripheral
        central.connect(peripheral, options: nil)
    }
    
    // connected to the device
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    {
        print("CentralManager() -> Successfully connected to \(peripheral.name ?? "-")")
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
        
        print("Peripheral() -> Serivces discovered")
        
        for srv in services {
            let uuid = srv.uuid.uuidString
            if uuid.hasSuffix(STFeature.serviceSuffixUUID) {
                print("Peripheral() -> Found common service, discovering chars")
            }
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
        
        for char in chars {
            
            if char.uuid == charDebugTermUUID {
                print("-> Found DEBUG char")
                termChar = char
                return
            }
            else if char.uuid == charDebugErrorUUID {
                //peripheral.setNotifyValue(true, for: char)
                errChar = char
                return
            }
            
            if !service.uuid.uuidString.hasSuffix(STFeature.serviceSuffixUUID) {
                continue
            }
            
            let data = char.uuid.data as NSData
            var beMask: UInt32 = 0
            data.getBytes(&beMask, length: 4)
            let mask = beMask.beToLe()
            
            let maskStr = String(format:"0x%08x", mask)
            
            var prop = ""
            if char.properties.contains(.notify) { prop = "notify"  }
            if char.properties.contains(.read) { prop += " read" }
            if char.properties.contains(.write) { prop += " write" }
            
            print("-> Char mask: \(maskStr), \(prop)")
            
            var featureBit: UInt32 = 0x80000000
            // starts with timestamp
            var offset = 2
            
            for _ in 0..<16 {
                // get mask
                featureBit >>= 1
                //guard var feature = featureMap[featureBit] else { break }
                
                // this feature is detected in mask
                if ( mask & featureBit ) != 0, let feature = featureMap[featureBit] {
                    feature.offset = offset
                    offset += feature.type.size
                    
                    // save this feature
                    if let sensor = sensors.first(where: { $0.char === char }) {
                        sensor.addFeature(feature)
                    }
                    else {
                        let sensor = STSensor(char: char)
                        sensor.addFeature(feature)
                        sensors.append(sensor)
                    }
                    
                    print("-> Found feature: \(feature.name)")
                    tableView.reloadData()
                    msg = "Found \(sensors.count) sensors"
                }
            }
            
            // enable notifications if this sensor was detected
            if  sensors.first(where: { $0.char === char }) != nil && char.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: char)
            }
        }
        
        // here we have the table of features
        //print("Detected features: \(detectedFeatures)")
    }
    
    var viewLastUpdatedTime = CACurrentMediaTime()
    
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

        default:
            if let idx = sensors.index(where: { $0.char === characteristic }) {
                let sensor = sensors[idx]
                sensor.processData(data)
//                var updatedIndexes: [IndexPath] = []
//                _ = sensor.features.reduce(idx) { r, _ in
//                    updatedIndexes.append( IndexPath(row: r, section: 0) )
//                    return r + 1
//                }
//
                let curTime = CACurrentMediaTime()
                if (curTime - viewLastUpdatedTime) > 0.1 {
                    viewLastUpdatedTime = curTime
                    tableView.reloadData()
//                    tableView.beginUpdates()
//                    tableView.reloadRows(at: updatedIndexes, with: .none)
//                    tableView.endUpdates()
                }
//
            }
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
                //print("==> Debug out message: \(stdOutMsg)")
                
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
                        peripheral?.setNotifyValue(false, for: termChar!)
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
            device.setNotifyValue(true, for: termChar)
            device.writeValue(data!, for: termChar, type: .withResponse )
        }
        else {
            print("==> Error: Device is not connected")
        }
    }
    
    @IBAction func reconnectButtonPressed(_ sender: UIButton) {
        if let manager = centralManager {
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
    

    // MARK: - TableView Delegate & DataSource
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sensors.reduce(0) { $0 + $1.features.count }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "sensorCell") as? SensorCell else {
            preconditionFailure("Can not deque cell for sensor view table")
        }
        
        var idx = 0
        for sensor in sensors {
            for feature in sensor.features {
                if  idx == indexPath.row {
                    cell.name.text = feature.name
                    cell.value.text = feature.lastValue
                    cell.units.text = feature.unit
                    return cell
                }
                idx += 1
            }
        }
        
        preconditionFailure("Can not find sensor data for indexPath: \(indexPath)")
    }
}

