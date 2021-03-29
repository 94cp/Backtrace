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

public func swift_demangle(_ mangledName: String) -> String {
    let cname = mangledName.withCString({ $0 })
    if let demangledName = get_swift_demangle(mangledName: cname, mangledNameLength: UInt(mangledName.utf8.count), outputBuffer: nil, outputBufferSize: nil, flags: 0) {
        defer { free(demangledName) }
        return String(cString: demangledName)
    }
    return mangledName
}

// https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlAddressInfo.swift
/// A wrapper around dl_info, used for symbolicating instruction addresses.
public struct AddressInfo {
    private let info: dl_info
    
    /// Address for which this struct was constructed
    public let address: UInt
    
    /// Construct for an address
    public init(address: UInt) {
        self.address = address

        var i = dl_info()
        dladdr(UnsafeRawPointer(bitPattern: address), &i)
        self.info = i
    }
    
    /// -returns: the "image" (shared object pathname) for the instruction
    public var image: String {
        if let dli_fname = info.dli_fname, let fname = String(validatingUTF8: dli_fname), let _ = fname.range(of: "/", options: .backwards, range: nil, locale: nil) {
            return (fname as NSString).lastPathComponent
        } else {
            return "???"
        }
    }
    
    /// - returns: the symbol nearest the address
    public var symbol: String {
        if let dli_sname = info.dli_sname, let sname = String(validatingUTF8: dli_sname) {
            return sname
        } else if let dli_fname = info.dli_fname, let _ = String(validatingUTF8: dli_fname) {
            return self.image
        } else {
            return String(format: "0x%1x", UInt(bitPattern: info.dli_saddr))
        }
    }
    
    public var demangleSymbol: String {
        return swift_demangle(self.symbol)
    }
    
    /// - returns: the address' offset relative to the nearest symbol
    public var offset: Int {
        if let dli_sname = info.dli_sname, let _ = String(validatingUTF8: dli_sname) {
            return Int(address - UInt(bitPattern: info.dli_saddr))
        } else if let dli_fname = info.dli_fname, let _ = String(validatingUTF8: dli_fname) {
            return Int(address - UInt(bitPattern: info.dli_fbase))
        } else {
            return Int(address - UInt(bitPattern: info.dli_saddr))
        }
    }
    
    /// - parameter index: the stack frame index
    /// - returns: a formatted string matching that used by NSThread.callStackSymbols
    public func formattedDescription(index: Int) -> String {
        return self.image.utf8CString.withUnsafeBufferPointer { (imageBuffer: UnsafeBufferPointer<CChar>) -> String in
            #if arch(x86_64) || arch(arm64)
                return String(format: "%-4ld%-35s 0x%016llx %@ + %ld", index, UInt(bitPattern: imageBuffer.baseAddress), self.address, self.demangleSymbol, self.offset)
            #else
                return String(format: "%-4d%-35s 0x%08lx %@ + %d", index, UInt(bitPattern: imageBuffer.baseAddress), self.address, self.demangleSymbol, self.offset)
            #endif
        }
    }
}
