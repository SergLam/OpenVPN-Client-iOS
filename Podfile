platform :ios, '13.0'
deployment_target = '13.0'

install! 'cocoapods', :disable_input_output_paths => true, :warn_for_unused_master_specs_repo => false, :deterministic_uuids => false

use_frameworks!
inhibit_all_warnings!

def shared_pods
  use_frameworks!
  pod 'OpenVPNAdapter', :git => 'https://github.com/deneraraujo/OpenVPNAdapter.git'
end

abstract_target 'App' do
  
  target 'VPNClient' do
    shared_pods
  end

  target 'TunnelProvider' do
    shared_pods
  end
  
  post_install do |installer|
    
     installer.pods_project.targets.each do |target|
           target.build_configurations.each do |config|
             
               config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
               config.build_settings['ENABLE_BITCODE'] = 'YES' # set 'NO' to disable DSYM uploading - usefull for third-party error logging SDK (like Firebase)
               
               if config.name == 'Debug' || config.name == 'Debug-Mock-API'
                 config.build_settings['OTHER_SWIFT_FLAGS'] = ['$(inherited)', '-Onone']
                 config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Owholemodule'
               end
       end
     end
     
     installer.generated_projects.each do |project|
       project.build_configurations.each do |bc|
         bc.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
       end
     end
     
   end

end
