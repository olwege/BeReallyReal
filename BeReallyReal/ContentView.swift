//
//  ContentView.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var store: PhotoStore
    @State private var showingCamera = false

    var body: some View {
        CalendarView()
            .environmentObject(store)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showingCamera = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .padding(20)
                        .background(.black)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
                .padding()
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraView()
                    .environmentObject(store)
            }
    }
}
