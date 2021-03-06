
//  AppDelegate.swift
//  OneWheel
//
//  Created by David Brodsky on 12/30/17.
//  Copyright © 2017 David Brodsky. All rights reserved.
//

import UIKit
import Onboard

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    let owManager = OneWheelManager()
    var stateVc : StateViewController?
    
    var onboarding = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        let databaseURL = try! FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ow.sqlite")
        owManager.db = try! OneWheelDatabase(databaseURL.path)
        owManager.start()
        
        self.stateVc = ((self.window?.rootViewController as! UINavigationController).topViewController as! StateViewController)
        stateVc!.owManager = owManager
        
        let didOnboard = OneWheelLocalData().getOnboarded()
        
        if !didOnboard {
            let firstPage = OnboardingContentViewController(title: "All aboard!", body: "Thanks for trying Float Deck. Here's some ProTips...", image: nil, buttonText: "Go on...") { () -> Void in
                // no-op
            }
            firstPage.movesToNextViewController = true
            let secondPage = OnboardingContentViewController(title: "One App at a Time", body: "Force close other OW apps to avoid problems connecting to your board.", image: nil, buttonText: "Next") { () -> Void in
                // no-op
            }
            secondPage.movesToNextViewController = true
            let thirdPage = OnboardingContentViewController(title: "Portrait & Landscape", body: "Portrait mode shows the last 60 seconds of data. Landscape shows your entire ride.", image: nil, buttonText: "Next") { () -> Void in
                // no-op
            }
            thirdPage.movesToNextViewController = true
            let fourthPage = OnboardingContentViewController(title: "Alerts Require Headphones", body: "You can change this via the in-app settings button. You can also review & control every alert type.", image: nil, buttonText: "Done") { () -> Void in
                
                OneWheelLocalData().setOnboarded(true)
                
                self.onboarding = false
                (self.window!.rootViewController as! UINavigationController).hidesBarsOnTap = true
                (self.window!.rootViewController as! UINavigationController).isToolbarHidden = false
                (self.window!.rootViewController as! UINavigationController).isNavigationBarHidden = false
                (self.window!.rootViewController as! UINavigationController).popViewController(animated: true)
            }
            fourthPage.movesToNextViewController = true
            let onboardingVC = OnboardingViewController(backgroundImage: UIImage(named: "ow-app"), contents: [firstPage, secondPage, thirdPage, fourthPage])
            
            onboarding = true
            (self.window!.rootViewController as! UINavigationController).hidesBarsOnTap = false
            (self.window!.rootViewController as! UINavigationController).isToolbarHidden = true
            (self.window!.rootViewController as! UINavigationController).isNavigationBarHidden = true

            (self.window!.rootViewController as! UINavigationController).pushViewController(onboardingVC!, animated: false)
            
//            self.window?.rootViewController = onboardingVC
        }
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
          owManager.flushBgStateQueue()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
    
    public func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if onboarding {
            return .portrait
        } else {
            return .allButUpsideDown
        }
    }
}

