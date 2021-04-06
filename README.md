# Swift获取任意线程调用栈

## 前言

研究了一些获取任意线程调用栈的开源库，基本是从[BSBacktraceLogger](https://github.com/bestswifter/BSBacktraceLogger)或[KSCrash](https://github.com/kstenerud/KSCrash)衍生出来的，核心实现都是C语言，无纯Swift实现的，所以搞了个[Backtrace](https://github.com/cp110/Backtrace)。

## 什么情况需要获取线程调用栈

分析性能瓶颈，崩溃原因等等。

## 如何获取线程调用栈

- 系统函数`Thread.callstackSymbols`（仅能获取当前线程调用栈，无法获取其它线程调用栈）
- Signal（调试较麻烦）[通过Signal handling(信号处理)获取任意线程调用栈](https://juejin.cn/post/6844903919617835021)
- Mach_thread（本文采取方式）

## 调用栈

每个线程都有自己的栈空间，线程中会有很多函数调用，每个函数调用都有自己的stack frame栈帧，栈就是由一个一个栈帧组成。

下面这个是ARM的栈帧布局图：



main stack frame为调用函数的栈帧，func1 stack frame为当前函数(被调用者)的栈帧，栈底在高地址，栈向下增长。图中FP就是栈基址，它指向函数的栈帧起始地址；SP则是函数的栈指针，它指向栈顶的位置。ARM压栈的顺序很是规矩，依次为当前函数指针PC、返回指针LR、栈指针SP、栈基址FP、传入参数个数及指针、本地变量和临时变量。如果函数准备调用另一个函数，跳转之前临时变量区先要保存另一个函数的参数。

## Mach_thread获取线程调用栈

从上图我们可以看到当前栈帧中FP的值存储的是上一个栈帧的FP地址。拿到本函数的FP寄存器，所指示的栈地址，出栈，就能得到调用函数的LR寄存器的值，然后就能通过dynsym动态链接表，找到对应的函数名。

```swift
let sf = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1) // 栈帧
defer { sf.deallocate() }

var outsize: vm_size_t = 0
let size: vm_size_t = vm_size_t(MemoryLayout.size(ofValue: sf) * 2)
    
var sf_kret = vm_read_overwrite(mach_task_self_, vm_address_t(__fp), size, vm_address_t(bitPattern: sf), &outsize)
if sf_kret != KERN_SUCCESS { return i }

while i < maxSymbols {
  guard let next_fp = sf.successor().pointee else { return i }
  stack[i] = next_fp
        
  guard let prev_fp = sf.pointee else { return i }
  sf_kret = vm_read_overwrite(mach_task_self_, vm_address_t(bitPattern: prev_fp), size, vm_address_t(bitPattern: sf), &outsize)
  if sf_kret != KERN_SUCCESS { return i }
        
  i += 1
}
```

## NSThread 转 Mach_thread

`NSThread`是对`pthread`的封装，系统提供了`pthread_mach_thread_np`函数将`pthread`转换为`Mach_thread`。如果能够按照`NSThread -> pthread -> Mach_thread`的路径转换，即可一步步获取到内核thread。但由于`NSThread`没有保留线程的 `pthread`，所以常规手段无法满足需求。

换种思路，系统提供了`pthread_from_mach_thread_np`函数将`Mach_thread`转换为`pthread`，提供了`pthread_getname_np`函数获取`pthread.name`，然后将其与`NSThread.name`比较即可获取到内核thread。

```swift
var machThread: thread_t {
    // 特殊处理：主线程转内核 thread（主线程设置 name 后无法用 pthread_getname_np 读取到）
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
```

## 函数调用栈符号化

- `backtrace_symbols`：在桥接文件中#import <execinfo.h>即可使用。（小技巧：亦可不用桥接文件，直接使用`@_silgen_name("C语言标准ABI的函数")`，本文即采取此方式）

```swift
/// 亦可在桥接文件中#import <execinfo.h>
/// 函数调用栈符号化
@_silgen_name("backtrace_symbols")
private func backtrace_symbols(_ stack: UnsafePointer<UnsafeMutableRawPointer?>!, _ frames: Int32) -> UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?
```

- `dladdr`：通过dladdr函数和Dl_info获得某个地址的符号信息。可以分解出`dli_fname`、`dli_fbase`、`dli_sname`、`dli_saddr`信息，比`backtrace_symbols`方式更加灵活。

```swift
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
```

## Swift命名重整

对于OC函数，我们无需进行命名重整。但Swift函数经过编译后的符号无法直接辨认，需要调用`swift_demangle`对重整过的符号进行还原。

```swift
/// https://github.com/apple/swift/blob/main/include/swift/Demangling/Demangle.h
@_silgen_name("swift_demangle")
private func get_swift_demangle(mangledName: UnsafePointer<CChar>?, mangledNameLength: UInt, outputBuffer: UnsafeMutablePointer<CChar>?, outputBufferSize: UnsafeMutablePointer<UInt>?, flags: UInt32) -> UnsafeMutablePointer<CChar>?
```

## 总结

以上[Backtrace](https://github.com/cp110/Backtrace)一些简单分析，它实现仅有**Backtrace.swift**一个文件，不到300行代码。但在编码过程中还是遇到了些问题的。

一开始参考[RCBacktrace](https://github.com/woshiccm/RCBacktrace)的**mach_backtrace.c**实现，核心代码如下，但在运行过程中偶尔会因为获取`cur__fp.pointee`时发生**EXC_BAD_ACCESS**崩溃。

```swift
guard var cur__fp = UnsafeMutablePointer<UnsafeMutableRawPointer?>(bitPattern: UInt(__fp)) else { return i }

while i < maxSymbols  {
    guard let prev__fp = UnsafeMutablePointer<UnsafeMutableRawPointer?>(bitPattern: UInt(bitPattern: cur__fp.pointee)) else { return i }
    
    stack[i] = cur__fp.successor().pointee
    cur__fp = prev__fp
    i += 1
}
```

后来参考[BSBacktraceLogger](https://github.com/bestswifter/BSBacktraceLogger)的`vm_read_overwrite`实现，核心代码如下，但`StackFrameEntry`会丢失部分**previous**栈帧。

```swift
/// 栈帧结构体
struct StackFrameEntry {
    /// 前一个栈帧地址
    var previous: UnsafePointer<StackFrameEntry>?
    /// 栈帧的函数返回地址
    var return_address: UInt = 0
}
```

```swift
guard __fp > 0 else { return i }

var sf = StackFrameEntry() // 栈帧
var outsize: vm_size_t = 0

var sf_kret = withUnsafeMutablePointer(to: &sf) {
    return vm_read_overwrite(mach_task_self_, vm_address_t(__fp), vm_size_t(MemoryLayout<StackFrameEntry>.size), vm_address_t(bitPattern: $0), &outsize)
}
if sf_kret != KERN_SUCCESS { return i }

while i < maxSymbols {
    guard sf.return_address > 0 else { return i }
    stack[i] = UnsafeMutableRawPointer(bitPattern: sf.return_address)
    
    guard let prev__sf = sf.previous, UInt(bitPattern: prev__sf) > 0 else { return i }
    sf_kret = withUnsafeMutablePointer(to: &sf) {
        return vm_read_overwrite(mach_task_self_, vm_address_t(bitPattern: prev__sf), vm_size_t(MemoryLayout<StackFrameEntry>.size), vm_address_t(bitPattern: $0), &outsize)
    }
    if sf_kret != KERN_SUCCESS { return i }
    
    i += 1
}
```

最后算是综合了两者，实现此[Backtrace](https://github.com/cp110/Backtrace)。如果你读完本文，知道为什么上面2种方式无法生效的原因，欢迎与我交流。

## 参考

- [获取任意线程调用栈的那些事](https://github.com/bestswifter/blog/blob/master/articles/objc-thread-backtrace.md)

- [iOS获取任意线程调用栈](https://juejin.cn/post/6844903944842395656#heading-6)