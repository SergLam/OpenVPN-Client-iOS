/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	This file contains the ClientTunnel class. The ClientTunnel class implements the client side of the SimpleTunnel tunneling protocol.
*/

import Foundation
import NetworkExtension

/// Make NEVPNStatus convertible to a string
extension NWTCPConnectionState: CustomStringConvertible {
	public var description: String {
		switch self {
			case .cancelled: return "Cancelled"
			case .connected: return "Connected"
			case .connecting: return "Connecting"
			case .disconnected: return "Disconnected"
			case .invalid: return "Invalid"
			case .waiting: return "Waiting"
        @unknown default:
            return "Unknown"
        }
	}
}

/// The client-side implementation of the SimpleTunnel protocol.
open class ClientTunnel: Tunnel {

	// MARK: Properties

	/// The tunnel connection.
	open var connection: NWTCPConnection?

	/// The last error that occurred on the tunnel.
	open var lastError: NSError?

	/// The previously-received incomplete message data.
	var previousData: NSMutableData?

	/// The address of the tunnel server.
	open var remoteHost: String?

	// MARK: Interface

	/// Start the TCP connection to the tunnel server.
	open func startTunnel(_ provider: NETunnelProvider) -> TunnelError? {

		guard let serverAddress = provider.protocolConfiguration.serverAddress else {
			return .badConfiguration
		}

		let endpoint: NWEndpoint

		if let colonRange = serverAddress.rangeOfCharacter(from: CharacterSet(charactersIn: ":"), options: [], range: nil) {
			// The server is specified in the configuration as <host>:<port>.
                      
            let hostname = serverAddress[serverAddress.startIndex..<colonRange.lowerBound]
			let portString = serverAddress[serverAddress.index(after: colonRange.lowerBound)..<serverAddress.endIndex]

			guard !hostname.isEmpty && !portString.isEmpty else {
				return .badConfiguration
			}

            endpoint = NWHostEndpoint(hostname:String(hostname), port:String(portString))
		}
		else {
			// The server is specified in the configuration as a Bonjour service name.
			endpoint = NWBonjourServiceEndpoint(name: serverAddress, type:Tunnel.serviceType, domain:Tunnel.serviceDomain)
		}

		// Kick off the connection to the server.
		connection = provider.createTCPConnection(to: endpoint, enableTLS:false, tlsParameters:nil, delegate:nil)

		// Register for notificationes when the connection status changes.
		connection!.addObserver(self, forKeyPath: "state", options: .initial, context: &connection)

		return nil
	}

	/// Close the tunnel.
	open func closeTunnelWithError(_ error: NSError?) {
		lastError = error
		closeTunnel()
	}

	/// Read a SimpleTunnel packet from the tunnel connection.
	func readNextPacket() {
		guard let targetConnection = connection else {
			closeTunnelWithError(TunnelError.badConnection as NSError)
			return
		}

		// First, read the total length of the packet.
		targetConnection.readMinimumLength(MemoryLayout<UInt32>.size, maximumLength: MemoryLayout<UInt32>.size) { data, error in
			if let readError = error {
                Util.output("[tunnel,error] Got an error on the tunnel connection: \(readError)")
				self.closeTunnelWithError(readError as NSError?)
				return
			}

			let lengthData = data

            guard lengthData?.count == MemoryLayout<UInt32>.size else {
                Util.output("[tunnel,info] Length data length (\(lengthData!.count)) != sizeof(UInt32) (\(MemoryLayout<UInt32>.size)")
				self.closeTunnelWithError(TunnelError.internalError as NSError)
				return
			}

			var totalLength: UInt32 = 0
            (lengthData! as NSData).getBytes(&totalLength, length: MemoryLayout<UInt32>.size)

			if totalLength > UInt32(Tunnel.maximumMessageSize) {
                Util.output("[tunnel,error] Got a length that is too big: \(totalLength)")
				self.closeTunnelWithError(TunnelError.internalError as NSError)
				return
			}

			totalLength -= UInt32(MemoryLayout<UInt32>.size)

			// Second, read the packet payload.
			targetConnection.readMinimumLength(Int(totalLength), maximumLength: Int(totalLength)) { data, error in
				if let payloadReadError = error {
                    Util.output("[tunnel,error] Got an error on the tunnel connection: \(payloadReadError)")
					self.closeTunnelWithError(payloadReadError as NSError?)
					return
				}

				let payloadData = data

                guard payloadData?.count == Int(totalLength) else {
                    Util.output("[tunnel,error] Payload data length (\(payloadData!.count)) != payload length (\(totalLength)")
					self.closeTunnelWithError(TunnelError.internalError as NSError)
					return
				}

                _ = self.handlePacket(payloadData!)

				self.readNextPacket()
			}
		}
	}

	/// Send a message to the tunnel server.
	open func sendMessage(_ messageProperties: [String: AnyObject], completionHandler: @escaping (Error?) -> Void) {
		guard let messageData = serializeMessage(messageProperties) else {
			completionHandler(TunnelError.internalError as NSError)
			return
		}
        
        connection?.write(messageData, completionHandler: completionHandler as (Error?) -> Void)
	}

	// MARK: NSObject

	/// Handle changes to the tunnel connection state.
	open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		guard keyPath == "state" && context?.assumingMemoryBound(to: Optional<NWTCPConnection>.self).pointee == connection else {
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
			return
		}

        Util.output("[tunnel,info] Tunnel connection state changed to \(connection!.state)")

		switch connection!.state {
			case .connected:
				if let remoteAddress = self.connection!.remoteAddress as? NWHostEndpoint {
					remoteHost = remoteAddress.hostname
				}

				// Start reading messages from the tunnel connection.
				readNextPacket()

				// Let the delegate know that the tunnel is open
				delegate?.tunnelDidOpen(self)

			case .disconnected:
				closeTunnelWithError(connection!.error as NSError?)

			case .cancelled:
				connection!.removeObserver(self, forKeyPath:"state", context:&connection)
				connection = nil
				delegate?.tunnelDidClose(self)

			default:
				break
		}
	}

	// MARK: Tunnel

	/// Close the tunnel.
	override open func closeTunnel() {
		super.closeTunnel()
		// Close the tunnel connection.
		if let TCPConnection = connection {
			TCPConnection.cancel()
		}

	}

	/// Write data to the tunnel connection.
	override func writeDataToTunnel(_ data: Data, startingAtOffset: Int) -> Int {
		connection?.write(data) { error in
			if error != nil {
				self.closeTunnelWithError(error as NSError?)
			}
		}
		return data.count
	}

	/// Handle a message received from the tunnel server.
	override func handleMessage(_ commandType: TunnelCommand, properties: [String: AnyObject], connection: Connection?) -> Bool {
		var success = true

		switch commandType {
			case .openResult:
				// A logical connection was opened successfully.
				guard let targetConnection = connection,
					let resultCodeNumber = properties[TunnelMessageKey.ResultCode.rawValue] as? Int,
					let resultCode = TunnelConnectionOpenResult(rawValue: resultCodeNumber)
					else
				{
					success = false
					break
				}

				targetConnection.handleOpenCompleted(resultCode, properties:properties as [NSObject : AnyObject])

			case .fetchConfiguration:
				guard let configuration = properties[TunnelMessageKey.Configuration.rawValue] as? [String: AnyObject]
					else { break }

				delegate?.tunnelDidSendConfiguration(self, configuration: configuration)
			
			default:
                Util.output("[tunnel,error] Tunnel received an invalid command")
				success = false
		}
		return success
	}

	/// Send a FetchConfiguration message on the tunnel connection.
	open func sendFetchConfiguation() {
		let properties = createMessagePropertiesForConnection(0, commandType: .fetchConfiguration)
		if !sendMessage(properties) {
            Util.output("[tunnel,error] Failed to send a fetch configuration message")
		}
	}
}

extension String {
    subscript (bounds: CountableClosedRange<Int>) -> String {
        let start = index(startIndex, offsetBy: bounds.lowerBound)
        let end = index(startIndex, offsetBy: bounds.upperBound)
        return String(self[start...end])
    }

    subscript (bounds: CountableRange<Int>) -> String {
        let start = index(startIndex, offsetBy: bounds.lowerBound)
        let end = index(startIndex, offsetBy: bounds.upperBound)
        return String(self[start..<end])
    }
}
