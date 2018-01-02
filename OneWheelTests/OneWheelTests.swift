//
//  OneWheelTests.swift
//  OneWheelTests
//
//  Created by David Brodsky on 12/30/17.
//  Copyright © 2017 David Brodsky. All rights reserved.
//

import XCTest
@testable import OneWheel

class OneWheelTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
    
    func testSpeedMonitor() {
        let sm = SpeedMonitor()
        
        assert(sm.passedBenchmark(0.0) == false)
        assert(sm.passedBenchmark(4.9) == false)
        assert(sm.passedBenchmark(5.9) == true)  // 5.0 benchmark
        assert(sm.passedBenchmark(6.1) == false)
        assert(sm.passedBenchmark(4.1) == false)

    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
