Pod::Spec.new do |s|
  s.name             = 'camera_native_details'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin to get native camera characteristics.'
  s.description      = 'Provides Android Camera2 characteristics; iOS/Web return default values for now.'
  s.homepage         = 'https://github.com/your-org/photobooth'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Photobooth' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
