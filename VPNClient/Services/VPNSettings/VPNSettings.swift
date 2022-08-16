//
//  VPNSettings.swift
//  VPNClient
//
//  Created by Serhii Liamtsev on 18/09/20.
//

import Foundation

/// Structure to store app settings on UserDefaults
public struct VPNSettings: Codable, VPNSettingsProtocol {
    private static let SETTINGS_KEY = "vpnclient_settings"
    
    private static var _selectedProfileId: String = ""
    private static var _profiles: [Profile] = []

    private var selectedProfileId: String
    private var profiles: [Profile]
    
    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()
    private static let appGroupDefaults = UserDefaults(suiteName:Config.appGroupName)!
    
    enum CodingKeys: String, CodingKey {
        case selectedProfileId = "selected_profile_id"
        case profiles = "profiles"
    }
    
    // MARK: - Life cycle
    public init() {
        selectedProfileId = VPNSettings._selectedProfileId
        profiles = VPNSettings.getProfiles()
    }
    
    // MARK: - Public
    public static func getSelectedProfile() -> Profile? {
        var selectedProfile: Profile?
        
        if let index = _profiles.firstIndex(where: { $0.profileId == _selectedProfileId }) {
            selectedProfile = _profiles[index]
        } else {
            selectedProfile = nil
        }
        
        return selectedProfile
    }
    
    public static func setSelectedProfile(profileId: String) {
        _selectedProfileId = profileId
        save()
    }
    
    public static func getProfiles() -> [Profile] {
        return _profiles
    }
    
    public static func saveProfile(profile: Profile) {
        if let index = _profiles.firstIndex(where: { $0.profileId == profile.profileId }) {
            _profiles[index] = profile
        } else {
            _profiles.append(profile)
        }

        save()
    }
    
    public static func load() -> VPNSettings {
        let settings_data = appGroupDefaults.value(forKey: SETTINGS_KEY) as? Data ?? nil
        let value = settings_data != nil ? getValue(data: settings_data!) : VPNSettings()
        
        _selectedProfileId = value.selectedProfileId
        _profiles = value.profiles
        
        return value
    }
    
    public static func clean() {
        appGroupDefaults.removeObject(forKey: SETTINGS_KEY)
        _selectedProfileId = ""
        _profiles = []
    }
    
    // MARK: - Private
    private static func save() {
        let settings = VPNSettings()
        
        do {
            let encodedData = try jsonEncoder.encode(settings)
            appGroupDefaults.set(encodedData, forKey: SETTINGS_KEY)
            _ = load()
        } catch {
            NSLog(error.localizedDescription)
        }
    }
    
    private static func getValue(data: Data) -> VPNSettings {
        var value: VPNSettings
        
        do {
            value = try jsonDecoder.decode(VPNSettings.self, from: data)
        } catch {
            value = VPNSettings()
            NSLog(error.localizedDescription)
        }
        
        return value
    }
}
