//
//  PreciseViewController.swift
//  FindMyCat
//
//  Created by Sahas Chitlange on 7/5/23.
//

import Foundation
import UIKit
import AVFoundation
import ARKit
import RealityKit
import NearbyInteraction
import os.log

class PreciseViewContoller: UIViewController {

    // MARK: - Declarations
    private let arrowImgView = UIImageView(image: UIImage(systemName: "arrow.up"))

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var arView: ARSCNView!
    let arConfig = ARWorldTrackingConfiguration()

    var dataChannel = DataCommunicationChannel()

    // Dictionary to associate each NI Session to the qorvoDevice using the uniqueID
    var referenceDict = [Int: NISession]()

    // A mapping from a discovery token to a name.
    var accessoryMap = [NIDiscoveryToken: String]()

    var configuration: NINearbyAccessoryConfiguration?
    var isConverged = false

    // Extras
    let logger = os.Logger(subsystem: "com.example.apple-samplecode.NINearbyAccessorySample", category: "AccessoryDemoViewController")

    // MARK: - View lifecycles
    override func viewDidLoad() {
        view.backgroundColor = .white
        setupSubviews()

        configureDataChannel()
    }

    // MARK: - Setup subviews

    private func setupSubviews() {
        setupCameraBlurLayer()
        setupArrowImage()
    }

    func setupArrowImage() {
        view.addSubview(arrowImgView)

        arrowImgView.tintColor = .black

        arrowImgView.translatesAutoresizingMaskIntoConstraints = false
        let widthConstraint = arrowImgView.widthAnchor.constraint(equalToConstant: 200)
        let heightConstraint = arrowImgView.heightAnchor.constraint(equalToConstant: 200)

        NSLayoutConstraint.activate([
            arrowImgView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            arrowImgView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            heightConstraint,
            widthConstraint
        ])
    }

    func setupCameraBlurLayer() {

        arView = ARSCNView(frame: view.bounds)
        view.addSubview(arView)

        // Set/start AR Session to provide camera assistance to new NI Sessions
        arConfig.worldAlignment = .gravity
        arConfig.isCollaborationEnabled = false
        arConfig.userFaceTrackingEnabled = false
        arConfig.initialWorldMap = nil
        arView.session = ARSession()
        arView.session.delegate = self
        arView.session.run(arConfig)

        // Apply blur effect to the background view
        let blurEffect = UIBlurEffect(style: .dark)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.frame = self.view.bounds
        self.view.addSubview(blurEffectView)
    }

    // MARK: - Setup Data channel
    private func configureDataChannel() {
        dataChannel.accessoryDataHandler = accessorySharedData

        // Prepare the data communication channel.
        dataChannel.accessoryDiscoveryHandler = accessoryInclude
        dataChannel.accessoryTimeoutHandler = accessoryRemove
        dataChannel.accessoryConnectedHandler = accessoryConnected
        dataChannel.accessoryDisconnectedHandler = accessoryDisconnected
        dataChannel.accessoryDataHandler = accessorySharedData
        dataChannel.start()

    }
    // MARK: - Data channel methods
    func accessoryInclude(index: Int) {

        if !qorvoDevices.isEmpty {
            logger.log("accessoryInclude: \(index)")
            let deviceID = qorvoDevices[0]?.bleUniqueID

            if (deviceID) != nil {
                // Connect to the accessory
                if qorvoDevices[0]?.blePeripheralStatus == statusDiscovered {
                    print("Connecting to Accessory")
                    connectToAccessory(deviceID!)
                } else {
                    return
                }
            }
        }

    }

    func accessoryRemove(deviceID: Int) {

    }

    func accessoryUpdate() {
        // Update devices
        qorvoDevices.forEach { (_) in
            print("@accessoryUpdate")
        }
    }

    func accessoryConnected(deviceID: Int) {
        // If no device is selected, select the new device
//        if selectedAccessory == -1 {
//            selectDevice(deviceID)
//        }

        // Create a NISession for the new device
        referenceDict[deviceID] = NISession()
        referenceDict[deviceID]?.delegate = self
        referenceDict[deviceID]?.setARSession(arView.session)

        let msg = Data([MessageId.initialize.rawValue])

        sendDataToAccessory(msg, deviceID)
    }

    func accessoryDisconnected(deviceID: Int) {

        referenceDict[deviceID]?.invalidate()
        // Remove the NI Session and Location values related to the device ID
        referenceDict.removeValue(forKey: deviceID)

//        if selectedAccessory == deviceID {
//            selectDevice(-1)
//        }

        accessoryUpdate()

        // Update device list and take other actions depending on the amount of devices
        let deviceCount = qorvoDevices.count

        if deviceCount == 0 {
//            selectDevice(-1)

            print("Accessory disconnected")
        }
    }

    func accessorySharedData(data: Data, accessoryName: String, deviceID: Int) {
        // The accessory begins each message with an identifier byte.
        // Ensure the message length is within a valid range.
        if data.count < 1 {
            print("Accessory shared data length was less than 1.")
            return
        }

        // Assign the first byte which is the message identifier.
        guard let messageId = MessageId(rawValue: data.first!) else {
            fatalError("\(data.first!) is not a valid MessageId.")
        }

        // Handle the data portion of the message based on the message identifier.
        switch messageId {
        case .accessoryConfigurationData:
            // Access the message data by skipping the message identifier.
            assert(data.count > 1)
            let message = data.advanced(by: 1)
            setupAccessory(message, name: accessoryName, deviceID: deviceID)
        case .accessoryUwbDidStart:
            handleAccessoryUwbDidStart(deviceID)
        case .accessoryUwbDidStop:
            handleAccessoryUwbDidStop(deviceID)
        case .configureAndStart:
            fatalError("Accessory should not send 'configureAndStart'.")
        case .initialize:
            fatalError("Accessory should not send 'initialize'.")
        case .stop:
            fatalError("Accessory should not send 'stop'.")
        // User defined/notification messages
        case .getReserved:
            print("Get not implemented in this version")
        case .setReserved:
            print("Set not implemented in this version")
        case .iOSNotify:
            print("Notification not implemented in this version")
        }
    }

    // MARK: - Accessory messages handling
    func setupAccessory(_ configData: Data, name: String, deviceID: Int) {
        print("Received configuration data from '\(name)'. Running session.")
        do {
            configuration = try NINearbyAccessoryConfiguration(data: configData)
            configuration?.isCameraAssistanceEnabled = true
        } catch {
            // Stop and display the issue because the incoming data is invalid.
            // In your app, debug the accessory data to ensure an expected
            // format.
            print("Failed to create NINearbyAccessoryConfiguration for '\(name)'. Error: \(error)")
            return
        }

        // Cache the token to correlate updates with this accessory.
        cacheToken(configuration!.accessoryDiscoveryToken, accessoryName: name)

        referenceDict[deviceID]?.run(configuration!)
        print("Accessory Session configured.")

    }

    func handleAccessoryUwbDidStart(_ deviceID: Int) {
        print("Accessory Session started.")

        // Update the device Status
        if let startedDevice = dataChannel.getDeviceFromUniqueID(deviceID) {
            startedDevice.blePeripheralStatus = statusRanging
        }

//        for case let cell as DeviceTableViewCell in accessoriesTable.visibleCells {
//            if cell.uniqueID == deviceID {
//                cell.selectAsset(.miniLocation)
//            }
//        }

        // Enables Location assets when Qorvo device starts ranging
        // TODO: Check if this is still necessary
//        enableLocation(true)
    }

    func handleAccessoryUwbDidStop(_ deviceID: Int) {
        print("Accessory Session stopped.")

        // Disconnect from device
        disconnectFromAccessory(deviceID)
    }

}

// MARK: - `ARSessionDelegate`.
extension PreciseViewContoller: ARSessionDelegate {
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        return false
    }
}

// MARK: - `NISessionDelegate`.
extension PreciseViewContoller: NISessionDelegate {

    func session(_ session: NISession, didGenerateShareableConfigurationData shareableConfigurationData: Data, for object: NINearbyObject) {
        guard object.discoveryToken == configuration?.accessoryDiscoveryToken else { return }

        // Prepare to send a message to the accessory.
        var msg = Data([MessageId.configureAndStart.rawValue])
        msg.append(shareableConfigurationData)

        let str = msg.map { String(format: "0x%02x, ", $0) }.joined()
        logger.info("Sending shareable configuration bytes: \(str)")

        // Send the message to the correspondent accessory.
        sendDataToAccessory(msg, deviceIDFromSession(session))
        print("Sent shareable configuration data.")
    }

    func session(_ session: NISession, didUpdateAlgorithmConvergence convergence: NIAlgorithmConvergence, for object: NINearbyObject?) {
        print("Convergence Status:\(convergence.status)")
        // TODO: To Refactor delete to only know converged or not

        guard let accessory = object else { return}

        switch convergence.status {
        case .converged:
            print("Horizontal Angle: \(accessory.horizontalAngle)")
            print("verticalDirectionEstimate: \(accessory.verticalDirectionEstimate)")
            print("Converged")
            isConverged = true
        case .notConverged([NIAlgorithmConvergenceStatus.Reason.insufficientLighting]):
            print("More light required")
            isConverged = false
        default:
            print("Try moving in a different direction...")
        }

    }
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let accessory = nearbyObjects.first else { return }
        guard let distance  = accessory.distance else { return }

        let deviceID = deviceIDFromSession(session)
        // print(NISession.deviceCapabilities)

        if let updatedDevice = dataChannel.getDeviceFromUniqueID(deviceID) {
            // set updated values
            updatedDevice.uwbLocation?.distance = distance

            if let direction = accessory.direction {
                updatedDevice.uwbLocation?.direction = direction
                updatedDevice.uwbLocation?.noUpdate  = false
            }
            // TODO: For IPhone 14 only
            else if isConverged {
                guard let horizontalAngle = accessory.horizontalAngle else {return}
                updatedDevice.uwbLocation?.direction = getDirectionFromHorizontalAngle(rad: horizontalAngle)
                updatedDevice.uwbLocation?.elevation = accessory.verticalDirectionEstimate.rawValue
                updatedDevice.uwbLocation?.noUpdate  = false
            } else {
                updatedDevice.uwbLocation?.noUpdate  = true
            }

            updatedDevice.blePeripheralStatus = statusRanging
        }

//        updateLocationFields(deviceID)
//        updateMiniFields(deviceID)

    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {

        // Retry the session only if the peer timed out.
        guard reason == .timeout else { return }
        print("Session timed out")

        // The session runs with one accessory.
        guard let accessory = nearbyObjects.first else { return }

        // Clear the app's accessory state.
        accessoryMap.removeValue(forKey: accessory.discoveryToken)

        // Get the deviceID associated to the NISession
        let deviceID = deviceIDFromSession(session)

        // Consult helper function to decide whether or not to retry.
        if shouldRetry(deviceID) {
            sendDataToAccessory(Data([MessageId.stop.rawValue]), deviceID)
            sendDataToAccessory(Data([MessageId.initialize.rawValue]), deviceID)
        }
    }

    func sessionWasSuspended(_ session: NISession) {
        print("Session was suspended.")
        let msg = Data([MessageId.stop.rawValue])

        sendDataToAccessory(msg, deviceIDFromSession(session))
    }

    func sessionSuspensionEnded(_ session: NISession) {
        print("Session suspension ended.")
        // When suspension ends, restart the configuration procedure with the accessory.
        let msg = Data([MessageId.initialize.rawValue])

        sendDataToAccessory(msg, deviceIDFromSession(session))
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        let deviceID = deviceIDFromSession(session)

        switch error {
        case NIError.invalidConfiguration:
            // Debug the accessory data to ensure an expected format.
            print("The accessory configuration data is invalid. Please debug it and try again.")
        case NIError.userDidNotAllow:
            handleUserDidNotAllow()
        case NIError.invalidConfiguration:
            print("Check the ARConfiguration used to run the ARSession")
        default:
            print("invalidated: \(error)")
            handleSessionInvalidation(deviceID)
        }
    }
}

// MARK: - Helpers.
extension PreciseViewContoller {

    func connectToAccessory(_ deviceID: Int) {
         do {
             try dataChannel.connectPeripheral(deviceID)
         } catch {
             print("Failed to connect to accessory: \(error)")
         }
    }

    func disconnectFromAccessory(_ deviceID: Int) {
         do {
             try dataChannel.disconnectPeripheral(deviceID)
         } catch {
             print("Failed to disconnect from accessory: \(error)")
         }
     }

    func sendDataToAccessory(_ data: Data, _ deviceID: Int) {
         do {
             try dataChannel.sendData(data, deviceID)
         } catch {
             print("Failed to send data to accessory: \(error)")
         }
     }

    func handleSessionInvalidation(_ deviceID: Int) {
        print("Session invalidated. Restarting.")
        // Ask the accessory to stop.
        sendDataToAccessory(Data([MessageId.stop.rawValue]), deviceID)

        // Replace the invalidated session with a new one.
        referenceDict[deviceID] = NISession()
        referenceDict[deviceID]?.delegate = self

        // Ask the accessory to stop.
        sendDataToAccessory(Data([MessageId.initialize.rawValue]), deviceID)
    }

    func shouldRetry(_ deviceID: Int) -> Bool {
        // Need to use the dictionary here, to know which device failed and check its connection state
        let qorvoDevice = dataChannel.getDeviceFromUniqueID(deviceID)

        if qorvoDevice?.blePeripheralStatus != statusDiscovered {
            return true
        }

        return false
    }

    func deviceIDFromSession(_ session: NISession) -> Int {
        var deviceID = -1

        for (key, value) in referenceDict {
            if value == session {
                deviceID = key
            }
        }

        return deviceID
    }

    func cacheToken(_ token: NIDiscoveryToken, accessoryName: String) {
        accessoryMap[token] = accessoryName
    }

    func handleUserDidNotAllow() {
        // Beginning in iOS 15, persistent access state in Settings.
        print("Nearby Interactions access required. You can change access for NIAccessory in Settings.")

        // Create an alert to request the user go to Settings.
        let accessAlert = UIAlertController(title: "Access Required",
                                            message: """
                                            NIAccessory requires access to Nearby Interactions for this sample app.
                                            Use this string to explain to users which functionality will be enabled if they change
                                            Nearby Interactions access in Settings.
                                            """,
                                            preferredStyle: .alert)
        accessAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        accessAlert.addAction(UIAlertAction(title: "Go to Settings", style: .default, handler: {_ in
            // Navigate the user to the app's settings.
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
            }
        }))

        // Preset the access alert.
        present(accessAlert, animated: true, completion: nil)
    }
}
