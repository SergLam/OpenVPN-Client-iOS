//
//  VPNSettingsProtocol.swift
//  VPNClient
//
//  Created by Serhii Liamtsev on 8/16/22.
//

import Foundation

public protocol VPNSettingsProtocol {
    
    static func getSelectedProfile() -> Profile?
    static func setSelectedProfile(profileId: String)
    static func getProfiles() -> [Profile]
    static func saveProfile(profile: Profile)
    static func load() -> VPNSettings
    static func clean()
}
