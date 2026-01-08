//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Metrics API open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Metrics API project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Metrics API project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension MetricsSystem {
    // MARK: - with(factory:mergingDimensions:)

    /// Runs the given closure with optional factory and/or dimensions bound to the task-local context.
    ///
    /// - Parameters:
    ///   - factory: Optional metrics factory to use within the closure.
    ///   - mergingDimensions: Optional dimensions to add to the context.
    ///   - operation: The closure to execute with the factory and dimensions bound.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<Result, Failure: Error>(
        factory: MetricsFactory? = nil,
        mergingDimensions: [(String, String)]? = nil,
        _ operation: () throws(Failure) -> Result
    ) rethrows -> Result {
        guard factory != nil || mergingDimensions != nil else {
            // No factory or dimensions, just run the operation
            return try operation()
        }

        if let factory = factory, let mergingDimensions = mergingDimensions {
            // Both factory and dimensions
            let currentDimensions = _taskLocalDimensions
            let mergedDimensions = self.mergeDimensions(currentDimensions, mergingDimensions)
            return try _withFactory(factory) {
                try _withDimensions(mergedDimensions, operation: operation)
            }
        } else if let factory = factory {
            // Only factory
            return try _withFactory(factory, operation: operation)
        } else {
            // Only dimensions
            let currentDimensions = _taskLocalDimensions
            let mergedDimensions = self.mergeDimensions(currentDimensions, mergingDimensions!)
            return try _withDimensions(mergedDimensions, operation: operation)
        }
    }

    /// Runs the given async closure with optional factory and/or dimensions bound to the task-local context.
    ///
    /// - Parameters:
    ///   - factory: Optional metrics factory to use within the closure.
    ///   - mergingDimensions: Optional dimensions to add to the context.
    ///   - operation: The async closure to execute with the factory and dimensions bound.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<Result, Failure: Error>(
        factory: MetricsFactory? = nil,
        mergingDimensions: [(String, String)]? = nil,
        _ operation: () async throws(Failure) -> Result
    ) async rethrows -> Result {
        guard factory != nil || mergingDimensions != nil else {
            // No factory or dimensions, just run the operation
            return try await operation()
        }

        if let factory = factory, let mergingDimensions = mergingDimensions {
            // Both factory and dimensions
            let currentDimensions = _taskLocalDimensions
            let mergedDimensions = self.mergeDimensions(currentDimensions, mergingDimensions)
            return try await _withFactory(factory) {
                try await _withDimensions(mergedDimensions, operation: operation)
            }
        } else if let factory = factory {
            // Only factory
            return try await _withFactory(factory, operation: operation)
        } else {
            // Only dimensions
            let currentDimensions = _taskLocalDimensions
            let mergedDimensions = self.mergeDimensions(currentDimensions, mergingDimensions!)
            return try await _withDimensions(mergedDimensions, operation: operation)
        }
    }
}
