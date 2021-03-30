//
//  AddressInfo.swift
//  Backtrace
//
//  Created by cp on 2021/2/21.
//

import Foundation

/// https://github.com/apple/swift/blob/main/include/swift/Demangling/Demangle.h
@_silgen_name("swift_demangle")
private func get_swift_demangle(mangledName: UnsafePointer<CChar>?, mangledNameLength: UInt, outputBuffer: UnsafeMutablePointer<CChar>?, outputBufferSize: UnsafeMutablePointer<UInt>?, flags: UInt32) -> UnsafeMutablePointer<CChar>?

/// 命名重整
public func swift_demangle(_ mangledName: String) -> String {
    let cname = mangledName.withCString({ $0 })
    if let demangledName = get_swift_demangle(mangledName: cname, mangledNameLength: UInt(mangledName.utf8.count), outputBuffer: nil, outputBufferSize: nil, flags: 0) {
        defer { free(demangledName) }
        return String(cString: demangledName)
    }
    return mangledName
}

// https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlAddressInfo.swift
/// 获取某地址符号信息
public struct AddressInfo {
    private let dlInfo: dl_info
    
    public let index: Int
    
    public let address: UInt
    
    public init(address: UInt, index: Int) {
        self.index = index
        self.address = address

        var dlInfo = dl_info()
        dladdr(UnsafeRawPointer(bitPattern: address), &dlInfo)
        self.dlInfo = dlInfo
    }
    
    public var image: String {
        if let dli_fname = dlInfo.dli_fname, let fname = String(validatingUTF8: dli_fname), let _ = fname.range(of: "/", options: .backwards, range: nil, locale: nil) {
            return (fname as NSString).lastPathComponent
        } else {
            return "???"
        }
    }
    
    public var symbol: String {
        if let dli_sname = dlInfo.dli_sname, let sname = String(validatingUTF8: dli_sname) {
            return sname
        } else if let dli_fname = dlInfo.dli_fname, let _ = String(validatingUTF8: dli_fname) {
            return self.image
        } else {
            return String(format: "0x%1x", UInt(bitPattern: dlInfo.dli_saddr))
        }
    }
    
    public var demangleSymbol: String {
        return swift_demangle(self.symbol)
    }
    
    public var offset: Int {
        if let dli_sname = dlInfo.dli_sname, let _ = String(validatingUTF8: dli_sname) {
            return Int(address - UInt(bitPattern: dlInfo.dli_saddr))
        } else if let dli_fname = dlInfo.dli_fname, let _ = String(validatingUTF8: dli_fname) {
            return Int(address - UInt(bitPattern: dlInfo.dli_fbase))
        } else {
            return Int(address - UInt(bitPattern: dlInfo.dli_saddr))
        }
    }
    
    public var description: String {
        return self.image.utf8CString.withUnsafeBufferPointer { (imageBuffer: UnsafeBufferPointer<CChar>) -> String in
            #if arch(x86_64) || arch(arm64)
            return String(format: "%-4ld%-35s 0x%016llx %@ + %ld", self.index, UInt(bitPattern: imageBuffer.baseAddress), self.address, self.demangleSymbol, self.offset)
            #else
            return String(format: "%-4d%-35s 0x%08lx %@ + %d", self.index, UInt(bitPattern: imageBuffer.baseAddress), self.address, self.demangleSymbol, self.offset)
            #endif
        }
    }
}
