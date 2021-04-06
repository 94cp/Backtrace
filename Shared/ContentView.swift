//
//  ContentView.swift
//  Shared
//
//  Created by chenp on 2021/2/21.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        Button("Main Call Stack") {
            DispatchQueue.global().async {
                print(Backtrace.callStackSymbolsOfMain().joined(separator: "\n"))
            }
        }
        Button("Current Call Stack") {
            DispatchQueue.global().async {
                print(Backtrace.callStackSymbolsOfCurrent().joined(separator: "\n"))
            }
        }
        Button("All Call Stack") {
            DispatchQueue.global().async {
                print(Backtrace.callStackSymbolsOfAll().map({ $0.joined(separator: "\n") }).joined(separator: "\n"))
            }
        }
        Button("Thread Current Call Stack") {
            DispatchQueue.global().async {
                print(Thread.callStackSymbols.joined(separator: "\n"))
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
