//
//  AppDelegate.swift
//  wallet
//
//  Created by Chris Downie on 10/4/16.
//  Copyright © 2016 Learning Machine, Inc. All rights reserved.
//

import UIKit
import JSONLD

private let sampleCertificateResetKey = "resetSampleCertificate"
private let enforceStrongOwnershipKey = "enforceStrongOwnership"

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    // The app has launched normally
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        Logger.main.info("Application was launched!")
        
        let configuration = ArgumentParser().parse(arguments: ProcessInfo.processInfo.arguments)
        do {
            try ConfigurationManager().configure(with: configuration)
        } catch KeychainErrors.invalidPassphrase {
            fatalError("Attempted to launch with invalid passphrase.")
        } catch {
            fatalError("Attempted to launch from command line with unknown error: \(error)")
        }

        Logger.main.debug("Managed issuers list url: \(Paths.managedIssuersListURL)")
        
        setupApplication()
        
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange), name:UserDefaults.didChangeNotification, object: nil)
        
        return true
    }
    
    // The app has launched from a universal link
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
        Logger.main.info("Application was launched from a user activity.")
        
        setupApplication()
        
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let url = userActivity.webpageURL {
            Logger.main.info("Application was launched with this url: \(url)")
            return importState(from: url)
        }

        return true
    }
    
    // The app is launching with a document
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        Logger.main.info("Application was launched with a document at \(url)")
        
        setupApplication()
        launchAddCertificate(at: url, showCertificate: true, animated: false)
        return true
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        Logger.main.info("Application entered the background.")
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        Logger.main.info("Application will terminate.")
    }
        
    func setupApplication() {
        self.window?.addSubview(JSONLD.shared.webView)

        UIButton.appearance().tintColor = .tintColor
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = .titleColor
        UILabel.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).tintColor = .titleColor
        UINavigationBar.appearance().tintColor = .tintColor
        
        UserDefaults.standard.register(defaults: [
            sampleCertificateResetKey : false
        ])
        
        // Reset state if needed
        resetSampleCertificateIfNeeded()
    }
    
    @objc func settingsDidChange() {
        resetSampleCertificateIfNeeded()
        enforceStrongOwnershipIfNeeded()
    }
    
    func resetSampleCertificateIfNeeded() {
        guard UserDefaults.standard.bool(forKey: sampleCertificateResetKey) else {
            return
        }
        defer {
            UserDefaults.standard.set(false, forKey: sampleCertificateResetKey)
        }
        
        guard let sampleCertURL = Bundle.main.url(forResource: "SampleCertificate.json", withExtension: nil) else {
            Logger.main.warning("Unable to load the sample certificate.")
            return
        }

        _ = launchAddCertificate(at: sampleCertURL)
    }
    
    func enforceStrongOwnershipIfNeeded() {
        guard UserDefaults.standard.bool(forKey: enforceStrongOwnershipKey) else {
            return
        }
        
        let issuerCollection = popToIssuerCollection()
        issuerCollection?.reloadCollectionView()
    }

    
    func importState(from url: URL) -> Bool {
        guard let fragment = url.fragment else {
            return false
        }
        
        var pathComponents = fragment.components(separatedBy: "/")
        guard pathComponents.count >= 1 else {
            return false
        }
        
        // For paths that start with /, the first one will be an empty string. So the true command name is the second element in the array.
        var commandName = pathComponents.removeFirst()
        if commandName == "" && pathComponents.count >= 1 {
            commandName = pathComponents.removeFirst()
        }
        
        switch commandName {
        case "import-certificate":
            guard pathComponents.count >= 1 else {
                return false
            }
            let encodedCertificateURL = pathComponents.removeFirst()
            if let decodedCertificateString = encodedCertificateURL.removingPercentEncoding,
                let certificateURL = URL(string: decodedCertificateString) {
                launchAddCertificate(at: certificateURL, showCertificate: true, animated: false)
                return true
            } else {
                return false
            }
            
        case "introduce-recipient":
            guard pathComponents.count >= 2 else {
                return false
            }
            let encodedIdentificationURL = pathComponents.removeFirst()
            let encodedNonce = pathComponents.removeFirst()
            if let decodedIdentificationString = encodedIdentificationURL.removingPercentEncoding,
                let identificationURL = URL(string: decodedIdentificationString),
                let nonce = encodedNonce.removingPercentEncoding {
                launchAddIssuer(at: identificationURL, with: nonce)
                return true
            } else {
                return false
            }

        default:
            return false
        }
    }
    
    func launchAddIssuer(at introductionURL: URL, with nonce: String) {
        let rootController = window?.rootViewController as? UINavigationController
        let issuerCollection = rootController?.viewControllers.first as? IssuerCollectionViewController
        
        issuerCollection?.autocompleteRequest = .addIssuer(identificationURL: introductionURL, nonce: nonce)
    }
    
    func launchAddCertificate(at url: URL, showCertificate: Bool = false, animated: Bool = true) {
        let rootController = window?.rootViewController as? UINavigationController
        let issuerCollection = rootController?.viewControllers.first as? IssuerCollectionViewController

        issuerCollection?.autocompleteRequest = .addCertificate(certificateURL: url, silently: !showCertificate, animated: animated)
    }
    
    func popToIssuerCollection() -> IssuerCollectionViewController? {
        let rootController = window?.rootViewController as? UINavigationController

        rootController?.presentedViewController?.dismiss(animated: false, completion: nil)
        _ = rootController?.popToRootViewController(animated: false)
        
        return rootController?.viewControllers.first as? IssuerCollectionViewController
    }

    func resetData() {
        // Delete all certificates
        do {
            for certificateURL in try FileManager.default.contentsOfDirectory(at: Paths.certificatesDirectory, includingPropertiesForKeys: nil, options: []) {
                try FileManager.default.removeItem(at: certificateURL)
            }
        } catch {
        }
        
        // Delete Issuers, Certificates folder, and everything else in documents directory.
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        do {
            let allFiles = try FileManager.default.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil, options: [])
            for fileURL in allFiles {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            
        }

    }
}
