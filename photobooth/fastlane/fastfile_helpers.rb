# frozen_string_literal: true

# Pure Ruby helpers for fastlane/Fastfile (no Fastlane DSL — keeps RuboCop complexity low).
module PhotoboothFastfile
  module_function

  def photobooth_root
    File.expand_path('..', __dir__)
  end

  def find_pubspec_path
    File.join(photobooth_root, 'pubspec.yaml')
  end

  def unknown_version
    { version_name: 'unknown', version_code: 'unknown' }
  end

  def parse_app_version(pubspec_path)
    return unknown_version unless File.exist?(pubspec_path)

    version_string = read_pubspec_version_string(pubspec_path)
    return unknown_version unless version_string&.include?('+')

    name, code = version_string.split('+', 2)
    { version_name: name.strip, version_code: code.strip }
  end

  def read_pubspec_version_string(pubspec_path)
    version_line = File.readlines(pubspec_path).find { |line| line.strip.start_with?('version:') }
    return nil unless version_line

    version_match = version_line.match(/version:\s*(.+)/)
    version_match&.[](1)&.strip
  end

  def app_version
    parse_app_version(find_pubspec_path)
  end

  def default_release_notes
    info = app_version
    "FotoZen #{info[:version_name]} (build #{info[:version_code]})"
  end

  def release_version_name
    now = Time.now
    "#{now.year}.#{now.month}.#{now.day}"
  end

  def android_aab_path
    File.join(photobooth_root, 'build/app/outputs/bundle/release/app-release.aab')
  end

  def ios_ipa_glob
    File.join(photobooth_root, 'build/ios/ipa/*.ipa')
  end

  def firebase_token_missing?(token)
    token.nil? || token.empty? || token.include?('your_firebase_ci_token')
  end

  def app_store_connect_key_id_missing?(key_id)
    key_id.nil? || key_id.empty? || key_id.include?('your_app_store_connect_key_id')
  end

  def app_store_connect_issuer_id_missing?(issuer_id)
    issuer_id.nil? || issuer_id.empty? || issuer_id.include?('your_app_store_connect_issuer_id')
  end
end
