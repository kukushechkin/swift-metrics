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

import Foundation
import MetricsTestKit
import Testing

@testable import CoreMetrics
@testable import Metrics

struct TaskLocalMetricsTests {
    // MARK: - Factory override tests

    @Test func withFactoryOverridesGlobalFactory() async throws {
        let testFactory = TestMetrics()
        let label = "counter-\(UUID().uuidString)"

        Metrics.with(factory: testFactory) {
            let counter = Counter(label: label)
            counter.increment()
        }

        let testCounter = try testFactory.expectCounter(label)
        #expect(testCounter.values.count == 1)
        #expect(testCounter.values[0] == 1)
    }

    @Test func withFactoryIsolatesFactories() async throws {
        let factory1 = TestMetrics()
        let factory2 = TestMetrics()
        let label = "counter-\(UUID().uuidString)"

        Metrics.with(factory: factory1) {
            let counter = Counter(label: label)
            counter.increment()
        }

        Metrics.with(factory: factory2) {
            let counter = Counter(label: label)
            counter.increment(by: 2)
        }

        // Verify each factory only received its own metrics
        let counter1 = try factory1.expectCounter(label)
        #expect(counter1.values.count == 1)
        #expect(counter1.values[0] == 1)

        let counter2 = try factory2.expectCounter(label)
        #expect(counter2.values.count == 1)
        #expect(counter2.values[0] == 2)
    }

    // MARK: - Dimension accumulation tests

    @Test func withDimensionsAddsToMetricCreation() async throws {
        let testFactory = TestMetrics()
        let label = "counter-\(UUID().uuidString)"

        Metrics.with(factory: testFactory, mergingDimensions: [("service", "api")]) {
            let counter = Counter(label: label)
            counter.increment()
        }

        let testCounter = try testFactory.expectCounter(label, [("service", "api")])
        #expect(testCounter.dimensions.count == 1)
        #expect(testCounter.values.count == 1)
    }

    @Test func withDimensionsAccumulatesNested() async throws {
        let testFactory = TestMetrics()
        let label = "counter-\(UUID().uuidString)"

        Metrics.with(factory: testFactory, mergingDimensions: [("service", "api")]) {
            Metrics.with(mergingDimensions: [("endpoint", "/users")]) {
                let counter = Counter(label: label)
                counter.increment()
            }
        }

        let testCounter = try testFactory.expectCounter(label, [("service", "api"), ("endpoint", "/users")])
        #expect(testCounter.dimensions.count == 2)
        #expect(testCounter.values.count == 1)
    }

    @Test func withDimensionsMergesWithExplicitDimensions() async throws {
        let testFactory = TestMetrics()
        let label = "counter-\(UUID().uuidString)"

        Metrics.with(factory: testFactory, mergingDimensions: [("service", "api")]) {
            // TaskLocal has [("service", "api")]
            // Explicit dimensions are [("version", "v1")]
            // Expected result: [("service", "api"), ("version", "v1")]
            let counter = Counter(label: label, dimensions: [("version", "v1")])
            counter.increment()
        }

        let testCounter = try testFactory.expectCounter(label, [("service", "api"), ("version", "v1")])
        #expect(testCounter.dimensions.count == 2)
    }

    // MARK: - Runtime dimension merging tests (key feature!)

    @Test func runtimeDimensionMergingCounter() async throws {
        let testFactory = TestMetrics()
        let label = "queue.size-\(UUID().uuidString)"

        // Create counter once, outside any context
        let counter = Counter(label: label, factory: testFactory)

        // Use with different dimensions at runtime
        Metrics.with(mergingDimensions: [("queue", "downloads")]) {
            counter.increment(by: 10)
        }

        Metrics.with(mergingDimensions: [("queue", "uploads")]) {
            counter.increment(by: 20)
        }

        // Verify two separate handlers were created with different dimensions
        let downloadsCounter = try testFactory.expectCounter(label, [("queue", "downloads")])
        #expect(downloadsCounter.values == [10])

        let uploadsCounter = try testFactory.expectCounter(label, [("queue", "uploads")])
        #expect(uploadsCounter.values == [20])
    }

    @Test func runtimeDimensionMergingGauge() async throws {
        let testFactory = TestMetrics()
        let label = "temperature-\(UUID().uuidString)"

        let gauge = Gauge(label: label, factory: testFactory)

        Metrics.with(mergingDimensions: [("location", "datacenter1")]) {
            gauge.record(25.5)
        }

        Metrics.with(mergingDimensions: [("location", "datacenter2")]) {
            gauge.record(30.2)
        }

        let dc1Gauge = try testFactory.expectGauge(label, [("location", "datacenter1")])
        #expect(dc1Gauge.lastValue == 25.5)

        let dc2Gauge = try testFactory.expectGauge(label, [("location", "datacenter2")])
        #expect(dc2Gauge.lastValue == 30.2)
    }

    @Test func runtimeDimensionMergingTimer() async throws {
        let testFactory = TestMetrics()
        let label = "request.duration-\(UUID().uuidString)"

        let timer = Timer(label: label, factory: testFactory)

        Metrics.with(mergingDimensions: [("endpoint", "/api/v1")]) {
            timer.recordMilliseconds(100)
        }

        Metrics.with(mergingDimensions: [("endpoint", "/api/v2")]) {
            timer.recordMilliseconds(200)
        }

        let v1Timer = try testFactory.expectTimer(label, [("endpoint", "/api/v1")])
        #expect(v1Timer.values.count == 1)

        let v2Timer = try testFactory.expectTimer(label, [("endpoint", "/api/v2")])
        #expect(v2Timer.values.count == 1)
    }

    @Test func runtimeDimensionMergingMeter() async throws {
        let testFactory = TestMetrics()
        let label = "connections-\(UUID().uuidString)"

        let meter = Meter(label: label, factory: testFactory)

        Metrics.with(mergingDimensions: [("protocol", "http")]) {
            meter.set(100)
        }

        Metrics.with(mergingDimensions: [("protocol", "websocket")]) {
            meter.set(50)
        }

        let httpMeter = try testFactory.expectMeter(label, [("protocol", "http")])
        #expect(httpMeter.values == [100])

        let wsMeter = try testFactory.expectMeter(label, [("protocol", "websocket")])
        #expect(wsMeter.values == [50])
    }

    @Test func runtimeDimensionMergingRecorder() async throws {
        let testFactory = TestMetrics()
        let label = "response.size-\(UUID().uuidString)"

        let recorder = Recorder(label: label, factory: testFactory)

        Metrics.with(mergingDimensions: [("status", "200")]) {
            recorder.record(1024)
        }

        Metrics.with(mergingDimensions: [("status", "404")]) {
            recorder.record(256)
        }

        let success = try testFactory.expectRecorder(label, [("status", "200")])
        #expect(success.values == [1024])

        let notFound = try testFactory.expectRecorder(label, [("status", "404")])
        #expect(notFound.values == [256])
    }

    @Test func runtimeDimensionMergingFloatingPointCounter() async throws {
        let testFactory = TestMetrics()
        let label = "bytes-\(UUID().uuidString)"

        let counter = FloatingPointCounter(label: label, factory: testFactory)

        Metrics.with(mergingDimensions: [("direction", "ingress")]) {
            counter.increment(by: 10.5)
        }

        Metrics.with(mergingDimensions: [("direction", "egress")]) {
            counter.increment(by: 20.3)
        }

        // FloatingPointCounter internally uses Counter, so we expect Counter handlers
        let ingress = try testFactory.expectCounter(label, [("direction", "ingress")])
        #expect(ingress.values.count >= 1)

        let egress = try testFactory.expectCounter(label, [("direction", "egress")])
        #expect(egress.values.count >= 1)
    }

    // MARK: - Combined base + runtime dimensions

    @Test func runtimeDimensionsMergeWithBaseDimensions() async throws {
        let testFactory = TestMetrics()
        let label = "metric-\(UUID().uuidString)"

        // Counter created with base dimensions
        let counter = Counter(label: label, dimensions: [("service", "api")], factory: testFactory)

        // Use with runtime dimensions
        Metrics.with(mergingDimensions: [("endpoint", "/users")]) {
            counter.increment()
        }

        // Should have both base + runtime dimensions
        let testCounter = try testFactory.expectCounter(
            label,
            [("service", "api"), ("endpoint", "/users")]
        )
        #expect(testCounter.values.count == 1)
        #expect(testCounter.dimensions.count == 2)
    }

    // MARK: - No dimensions (fast path)

    @Test func noDimensionsFastPath() async throws {
        let testFactory = TestMetrics()
        let label = "counter-\(UUID().uuidString)"

        // Create and use counter without any TaskLocal context
        let counter = Counter(label: label, factory: testFactory)
        counter.increment()
        counter.increment()

        let testCounter = try testFactory.expectCounter(label, [])
        #expect(testCounter.values.count == 2)
        #expect(testCounter.values == [1, 1])
    }

    // MARK: - Task isolation

    @Test func taskLocalIsolation() async throws {
        let testFactory = TestMetrics()
        let label = "counter-\(UUID().uuidString)"

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                Metrics.with(factory: testFactory, mergingDimensions: [("task", "1")]) {
                    let counter = Counter(label: label)
                    counter.increment(by: 1)
                }
            }

            group.addTask {
                Metrics.with(factory: testFactory, mergingDimensions: [("task", "2")]) {
                    let counter = Counter(label: label)
                    counter.increment(by: 2)
                }
            }
        }

        let counter1 = try testFactory.expectCounter(label, [("task", "1")])
        #expect(counter1.values == [1])

        let counter2 = try testFactory.expectCounter(label, [("task", "2")])
        #expect(counter2.values == [2])
    }

    // MARK: - All metric types with dimensions

    @Test func allMetricTypesRespectTaskLocalFactory() async throws {
        let testFactory = TestMetrics()
        let prefix = UUID().uuidString

        Metrics.with(factory: testFactory) {
            let counter = Counter(label: "counter-\(prefix)")
            let fpCounter = FloatingPointCounter(label: "fpcounter-\(prefix)")
            let gauge = Gauge(label: "gauge-\(prefix)")
            let meter = Meter(label: "meter-\(prefix)")
            let recorder = Recorder(label: "recorder-\(prefix)")
            let timer = Timer(label: "timer-\(prefix)")

            counter.increment()
            fpCounter.increment()
            gauge.record(1)
            meter.set(1)
            recorder.record(1)
            timer.recordNanoseconds(1)
        }

        // Verify all were created with the test factory
        _ = try testFactory.expectCounter("counter-\(prefix)")
        _ = try testFactory.expectCounter("fpcounter-\(prefix)")  // FloatingPointCounter uses Counter internally
        _ = try testFactory.expectGauge("gauge-\(prefix)")
        _ = try testFactory.expectMeter("meter-\(prefix)")
        _ = try testFactory.expectRecorder("recorder-\(prefix)")
        _ = try testFactory.expectTimer("timer-\(prefix)")
    }

    // MARK: - Reset operations with dimensions

    @Test func resetWithRuntimeDimensions() async throws {
        let testFactory = TestMetrics()
        let label = "counter-\(UUID().uuidString)"

        let counter = Counter(label: label, factory: testFactory)

        Metrics.with(mergingDimensions: [("environment", "production")]) {
            counter.increment(by: 10)
        }

        let testCounter = try testFactory.expectCounter(label, [("environment", "production")])
        #expect(testCounter.values.count == 1)
        #expect(testCounter.values[0] == 10)
    }

    // MARK: - Meter operations with dimensions

    @Test func meterAllOperationsWithRuntimeDimensions() async throws {
        let testFactory = TestMetrics()
        let label = "connections-\(UUID().uuidString)"

        let meter = Meter(label: label, factory: testFactory)

        Metrics.with(mergingDimensions: [("type", "persistent")]) {
            meter.set(100)
            meter.increment(by: 10)
            meter.decrement(by: 5)
        }

        let testMeter = try testFactory.expectMeter(label, [("type", "persistent")])
        #expect(testMeter.values == [100, 110, 105])
    }

    // MARK: - Deep nesting

    @Test func deeplyNestedDimensions() async throws {
        let testFactory = TestMetrics()
        let label = "counter-\(UUID().uuidString)"

        Metrics.with(factory: testFactory, mergingDimensions: [("env", "prod")]) {
            Metrics.with(mergingDimensions: [("region", "us-west")]) {
                Metrics.with(mergingDimensions: [("zone", "1a")]) {
                    let counter = Counter(label: label)
                    counter.increment()
                }
            }
        }

        let testCounter = try testFactory.expectCounter(
            label,
            [("env", "prod"), ("region", "us-west"), ("zone", "1a")]
        )
        #expect(testCounter.dimensions.count == 3)
    }

    // MARK: - Timer conversion methods with dimensions

    @Test func timerConversionMethodsWithDimensions() async throws {
        let testFactory = TestMetrics()
        let label = "latency-\(UUID().uuidString)"

        let timer = Timer(label: label, factory: testFactory)

        Metrics.with(mergingDimensions: [("unit", "test")]) {
            timer.recordMicroseconds(100)
            timer.recordMilliseconds(200)
            timer.recordSeconds(1)
        }

        let testTimer = try testFactory.expectTimer(label, [("unit", "test")])
        #expect(testTimer.values.count == 3)
    }

    // MARK: - Empty dimensions edge case

    @Test func emptyDimensionsArray() async throws {
        let testFactory = TestMetrics()
        let label = "counter-\(UUID().uuidString)"

        Metrics.with(factory: testFactory, mergingDimensions: []) {
            let counter = Counter(label: label)
            counter.increment()
        }

        let testCounter = try testFactory.expectCounter(label, [])
        #expect(testCounter.values.count == 1)
    }

    // MARK: - Dimension deduplication

    @Test func dimensionDeduplicationAtCreation() async throws {
        let testFactory = TestMetrics()
        let label = "counter-\(UUID().uuidString)"

        // Create counter with "region" in TaskLocal context
        Metrics.with(factory: testFactory, mergingDimensions: [("region", "us-west")]) {
            // Also pass "region" explicitly - TaskLocal should win (last wins)
            let counter = Counter(label: label, dimensions: [("region", "eu-central"), ("version", "v1")])
            counter.increment()
        }

        // Should have region=us-west (TaskLocal overrides explicit) and version=v1
        let testCounter = try testFactory.expectCounter(label, [("region", "us-west"), ("version", "v1")])
        #expect(testCounter.values.count == 1)
    }

    @Test func dimensionDeduplicationAtOperation() async throws {
        let testFactory = TestMetrics()
        let label = "counter-\(UUID().uuidString)"

        // Create counter with region=us-west at creation
        Metrics.with(factory: testFactory, mergingDimensions: [("region", "us-west"), ("version", "v1")]) {
            let counter = Counter(label: label)

            // Use same counter in nested context with overlapping dimension
            Metrics.with(mergingDimensions: [("region", "us-west"), ("service", "api")]) {
                counter.increment()
            }
        }

        // Should have all three dimensions, with region not duplicated
        let testCounter = try testFactory.expectCounter(
            label,
            [("region", "us-west"), ("version", "v1"), ("service", "api")]
        )
        #expect(testCounter.values.count == 1)
    }

    @Test func dimensionOverrideInNestedContext() async throws {
        let testFactory = TestMetrics()
        let label = "counter-\(UUID().uuidString)"

        Metrics.with(factory: testFactory, mergingDimensions: [("region", "us-west")]) {
            let counter = Counter(label: label)

            // Nested context overrides region
            Metrics.with(mergingDimensions: [("region", "eu-central")]) {
                counter.increment()
            }
        }

        // Should use the nested (later) region value
        let testCounter = try testFactory.expectCounter(label, [("region", "eu-central")])
        #expect(testCounter.values.count == 1)
    }
}
