Pod::Spec.new do |s|
  s.name             = 'face_count'
  s.version          = '0.0.1'
  s.summary          = 'On-device face counting for Flutter (Vision on iOS).'
  s.description      = 'Face count via Apple Vision on iOS; ML Kit on Android.'
  s.homepage         = 'https://github.com/your-org/photobooth'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Photobooth' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'face_count/Sources/face_count/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '26.0'
  s.frameworks = 'Vision'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
