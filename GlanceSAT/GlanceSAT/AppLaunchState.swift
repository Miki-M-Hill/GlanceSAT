//
//  AppLaunchState.swift
//  GlanceSAT
//

import Foundation

/// Global cold-launch gate — set when background bootstrap finishes.
enum AppLaunchState {
    @MainActor static var isDataLoaded = false
}
