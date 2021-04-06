//
//  Backtrace.swift
//  Backtrace
//
//  Created by chenp on 2021/2/21.
//

/// https://github.com/woshiccm/RCBacktrace
/// https://github.com/bestswifter/blog/blob/master/articles/objc-thread-backtrace.md

import Foundation

/// 亦可在桥接文件中#import <execinfo.h>
/// 函数调用栈符号化
/// - Parameters:
///   - stack: 函数调用栈
///   - frames: 函数调用栈层数
@_silgen_name("backtrace_symbols")
private func backtrace_symbols(_ stack: UnsafePointer<UnsafeMutableRawPointer?>!, _ frames: Int32) -> UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?

/// https://github.com/apple/swift/blob/main/include/swift/Demangling/Demangle.h
@_silgen_name("swift_demangle")
private func get_swift_demangle(mangledName: UnsafePointer<CChar>?, mangledNameLength: UInt, outputBuffer: UnsafeMutablePointer<CChar>?, outputBufferSize: UnsafeMutablePointer<UInt>?, flags: UInt32) -> UnsafeMutablePointer<CChar>?

/// 命名重整
private func swift_demangle(_ mangledName: String) -> String {
    let cname = mangledName.withCString({ $0 })
    if let demangledName = get_swift_demangle(mangledName: cname, mangledNameLength: UInt(mangledName.utf8.count), outputBuffer: nil, outputBufferSize: nil, flags: 0) {
        defer { free(demangledName) }
        return String(cString: demangledName)
    }
    return mangledName
}

public struct Backtrace {
    public static func callStackSymbols(_ thread: Thread, prefix: Bool = true) -> [String] {
        let mach = thread.machThread
        var symbols = mach.callStackSymbols
        if prefix {
            let prefix = "Backtrace of : \(mach.description)"
            symbols.insert(prefix, at: 0)
        }
        return symbols
    }
    
    public static func callStackSymbolsOfMain(prefix: Bool = true) -> [String] {
        return callStackSymbols(.main, prefix: prefix)
    }
    
    public static func callStackSymbolsOfCurrent(prefix: Bool = true) -> [String] {
        return callStackSymbols(.current, prefix: prefix)
    }
    
    public static func callStackSymbolsOfAll(prefix: Bool = true) -> [[String]] {
        var allSymbols: [[String]] = []
        
        var count: mach_msg_type_number_t = 0
        var threads: thread_act_array_t!
        
        // 获取所有内核 thread
        if task_threads(mach_task_self_, &(threads), &count) != KERN_SUCCESS {
            let mach = mach_thread_self()
            var symbols = mach.callStackSymbols
            if prefix {
                let prefix = "Backtrace of : \(mach.description)"
                symbols.insert(prefix, at: 0)
            }
            allSymbols.append(symbols)
        } else {
            for i in 0..<count {
                let mach = threads[Int(i)]
                var symbols = mach.callStackSymbols
                if prefix {
                    let prefix = "Backtrace of : \(mach.description)"
                    symbols.insert(prefix, at: 0)
                }
                allSymbols.append(symbols)
            }
        }
        return allSymbols
    }
}

extension Thread {
    /// NSThread 转内核 thread
    fileprivate var machThread: thread_t {
        // 主线程转内核 thread（主线程设置 name 后无法用 pthread_getname_np 读取到）
        if isMainThread {
            var main_thread_t: thread_t?
            if !Thread.isMainThread {
                DispatchQueue.main.sync {
                    main_thread_t = mach_thread_self()
                }
            }
            return main_thread_t ?? mach_thread_self()
        }
        
        var count: mach_msg_type_number_t = 0
        var threads: thread_act_array_t!
    
        // 获取所有内核 thread
        guard task_threads(mach_task_self_, &(threads), &count) == KERN_SUCCESS else {
            return mach_thread_self()
        }
        
        let originName = name
        defer { name = originName }

        name = String(Int(Date().timeIntervalSince1970))
        
        for i in 0..<count {
            let machThread = threads[Int(i)]
            if let p_thread = pthread_from_mach_thread_np(machThread) {
                var name: [Int8] = Array<Int8>(repeating: 0, count: 128)
                pthread_getname_np(p_thread, &name, name.count)
                if self.name == String(cString: name) {
                    return machThread
                }
            }
        }
        
        return mach_thread_self()
    }
}

extension thread_t {
    fileprivate var callStackSymbols: [String] {
        let maxSize = 128
        let addrs = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: maxSize)
        defer { addrs.deallocate() }
        
        let count = backtrace(addrs, maxSize)
        var symbols: [String] = []
        
        // 命名重整 方式1
        let buf = UnsafeBufferPointer(start: addrs, count: count)
        symbols = buf.enumerated().map({
            guard let addr = $0.element else {
                return "<null>"
            }
            return dlSymbol(UInt(bitPattern: addr), $0.offset)
        })
        
//        // 命名重整 方式2
//        if let bs = backtrace_symbols(addrs, Int32(count)) {
//            symbols = UnsafeBufferPointer(start: bs, count: count).map {
//                guard let symbol = $0 else {
//                    return "<null>"
//                }
//                return demangleSymbol(String(cString: symbol))
//            }
//            free(bs)
//        }
//
        return symbols
    }
}

extension thread_t {
    /// dladdr获取某个地址的符号信息
    private func dlSymbol(_ address: UInt, _ index: Int) -> String {
        var dlInfo = dl_info()
        dladdr(UnsafeRawPointer(bitPattern: address), &dlInfo)
        
        var image = "??"
        if let dli_fname = dlInfo.dli_fname,
           let fname = String(validatingUTF8: dli_fname),
           let _ = fname.range(of: "/", options: .backwards, range: nil, locale: nil) {
            image = (fname as NSString).lastPathComponent
        }
        
        var symbol = "??"
        if let dli_sname = dlInfo.dli_sname, let sname = String(validatingUTF8: dli_sname) {
            symbol = sname
        } else if let dli_fname = dlInfo.dli_fname, let _ = String(validatingUTF8: dli_fname), image != "??" {
            symbol = image
        } else {
            symbol = String(format: "0x%1x", UInt(bitPattern: dlInfo.dli_saddr))
        }
        
        let demangleSymbol = swift_demangle(symbol)
        
        var offset: UInt = 0
        if let dli_sname = dlInfo.dli_sname, let _ = String(validatingUTF8: dli_sname) {
            offset = address - UInt(bitPattern: dlInfo.dli_saddr)
        } else if let dli_fname = dlInfo.dli_fname, let _ = String(validatingUTF8: dli_fname) {
            offset = address - UInt(bitPattern: dlInfo.dli_fbase)
        } else {
            offset = address - UInt(bitPattern: dlInfo.dli_saddr)
        }
        
        return image.utf8CString.withUnsafeBufferPointer { (imageBuffer: UnsafeBufferPointer<CChar>) -> String in
            #if arch(x86_64) || arch(arm64)
            return String(format: "%-4ld%-35s 0x%016llx %@ + %ld", index, UInt(bitPattern: imageBuffer.baseAddress), address, demangleSymbol, offset)
            #else
            return String(format: "%-4d%-35s 0x%08lx %@ + %d", index, UInt(bitPattern: imageBuffer.baseAddress), address, demangleSymbol, offset)
            #endif
        }
    }
    
    /// 命名重整
    private func demangleSymbol(_ symbol: String) -> String {
        guard let regexp = try? NSRegularExpression(pattern: "^(?:\\S+ +){3}(\\S+) ", options: []),
              let match = regexp.firstMatch(in: symbol, options: [], range: NSMakeRange(0, symbol.utf16.count)),
              match.numberOfRanges > 1  else { return symbol }
        
        let sname = (symbol as NSString).substring(with: match.range(at: 1))
        let demangleSname = swift_demangle(sname)

        return symbol.replacingOccurrences(of: sname, with: demangleSname)
    }
}

extension thread_t {
    // 获取 内核 thread 调用栈信息
    private func backtrace(_ stack: UnsafeMutablePointer<UnsafeMutableRawPointer?>, _ maxSymbols: Int) -> Int {
        #if arch(i386)
        let THREAD_STATE_FLAVOR = x86_THREAD_STATE
        let THREAD_STATE_COUNT = mach_msg_type_number_t(MemoryLayout<x86_thread_state_t>.size / MemoryLayout<Int32>.size)
        #elseif arch(x86_64)
        let THREAD_STATE_FLAVOR = x86_THREAD_STATE64
        let THREAD_STATE_COUNT = mach_msg_type_number_t(MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<Int32>.size)
        #elseif arch(arm)
        let THREAD_STATE_FLAVOR = ARM_THREAD_STATE
        let THREAD_STATE_COUNT = mach_msg_type_number_t(MemoryLayout<arm_thread_state_t>.size / MemoryLayout<UInt32>.size)
        #elseif arch(arm64)
        let THREAD_STATE_FLAVOR = ARM_THREAD_STATE64
        let THREAD_STATE_COUNT = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)
        #else
        #error("Current CPU Architecture is not supported")
        #endif
        
        var i = 0
        
        let mc = mcontext_t.allocate(capacity: 1)
        defer { mc.deallocate() }
        
        var mContext = mc.pointee
        var stateCount = THREAD_STATE_COUNT
        
        let kret = withUnsafeMutablePointer(to: &(mContext.__ss)) {
            $0.withMemoryRebound(to: natural_t.self, capacity: 1) {
                thread_get_state(self, THREAD_STATE_FLAVOR, $0, &stateCount)
            }
        }
        if kret != KERN_SUCCESS { return i }
        
        #if arch(i386)
        let __fp = mContext.__ss.__ebp
        let __pc = mContext.__ss.__eip
        #elseif arch(x86_64)
        let __fp = mContext.__ss.__rbp
        let __pc = mContext.__ss.__rip
        #elseif arch(arm)
        let __fp = mContext.__ss.__r[7]
        let __pc = mContext.__ss.__pc
        let __lr = mContext.__ss.__lr
        #elseif arch(arm64)
        let __fp = mContext.__ss.__fp
        let __pc = mContext.__ss.__pc
        let __lr = mContext.__ss.__lr
        #endif
        
        // 指令地址（指令寄存器存储，指向处理器下条等待执行的指令地址（代码内的偏移量），每次执行完 __pc 会增加）
        guard __pc > 0, let pc = UnsafeMutableRawPointer(bitPattern: UInt(__pc)) else { return i }
        stack[i] = pc
        i += 1
        
        #if arch(arm) || arch(arm64)
        // __lr链接寄存器，保存返回上一层调用的地址
        if __lr > 0, let lr = UnsafeMutableRawPointer(bitPattern: UInt(__lr)) {
            stack[i] = lr
            i += 1
        }
        #endif
        
        // 当前栈帧中FP的值存储的是上一个栈帧的FP地址
        guard __fp > 0 else { return i }
        
        let sf = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1) // 栈帧
        defer { sf.deallocate() }
        
        var outsize: vm_size_t = 0
        let size: vm_size_t = vm_size_t(MemoryLayout.size(ofValue: sf) * 2)
        
        var sf_kret = vm_read_overwrite(mach_task_self_, vm_address_t(__fp), size, vm_address_t(bitPattern: sf), &outsize)
        if sf_kret != KERN_SUCCESS { return i }
        
        while i < maxSymbols {
            guard let next_fp = sf.successor().pointee else { return i }
            stack[i] = next_fp
            
            guard let prev_fp = sf.pointee, UInt(bitPattern: prev_fp) > 0 else { return i }
            sf_kret = vm_read_overwrite(mach_task_self_, vm_address_t(bitPattern: prev_fp), size, vm_address_t(bitPattern: sf), &outsize)
            if sf_kret != KERN_SUCCESS { return i }
            
            i += 1
        }
        
        return i
    }
}
