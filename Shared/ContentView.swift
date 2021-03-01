//
//  ContentView.swift
//  Shared
//
//  Created by cp on 2021/2/24.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
            .padding()
        Button("Backtrace") {
            print("这是系统方法的MainThreadStackSymbols")
            print(Thread.callStackSymbols.joined(separator: "\n"))
            print("这是Backtrace方法的MainThreadStackSymbols")
            print(Backtrace.backtraceMainThread())
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
