# frozen_string_literal: true

# Pure Ruby helpers for fastlane/Fastfile (no Fastlane DSL — keeps RuboCop complexity low).
module PhotoboothFastfile
  ANDROID_AAB_RELATIVE_PATHS = %w[
    build/app/outputs/bundle/release/app-release.aab
    build/app/outputs/bundle/release/photobooth-release.aab
  ].freeze

  ANDROID_APK_RELATIVE_PATHS = %w[
    build/app/outputs/flutter-apk/app-release.apk
    build/app/outputs/flutter-apk/photobooth-release.apk
    build/app/outputs/apk/release/photobooth-release.apk
    build/app/outputs/apk/release/app-release.apk
  ].freeze

  # bundle exec injects these so Homebrew `pod` looks "broken" to Flutter.
  BUNDLER_ENV_UNSET_KEYS = %w[
    BUNDLE_GEMFILE
    BUNDLE_BIN_PATH
    BUNDLER_SETUP
    BUNDLER_VERSION
    RUBYOPT
    RUBYLIB
    GEM_HOME
    GEM_PATH
  ].freeze

  PHOTBOOTH_DOTENV_FILES = %w[.env .env.local].freeze

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
    version_line = File.readlines(pubspec_path, encoding: 'UTF-8').find { |line| line.strip.start_with?('version:') }
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

  def first_existing_path(relative_paths)
    relative_paths.map { |relative| File.join(photobooth_root, relative) }.find { |path| File.exist?(path) }
  end

  def android_aab_path
    first_existing_path(ANDROID_AAB_RELATIVE_PATHS) ||
      File.join(photobooth_root, ANDROID_AAB_RELATIVE_PATHS.first)
  end

  def android_apk_path
    first_existing_path(ANDROID_APK_RELATIVE_PATHS) ||
      File.join(photobooth_root, ANDROID_APK_RELATIVE_PATHS.first)
  end

  def ios_ipa_glob
    File.join(photobooth_root, 'build/ios/ipa/*.ipa')
  end

  def load_photobooth_dotenv!
    PHOTBOOTH_DOTENV_FILES.each do |name|
      apply_dotenv_file(File.join(photobooth_root, name))
    end
  end

  def apply_dotenv_file(path)
    return unless File.exist?(path)

    File.readlines(path, encoding: 'UTF-8').each { |line| apply_dotenv_line(line) }
  end

  def apply_dotenv_line(line)
    stripped = line.strip
    return if stripped.empty? || stripped.start_with?('#')

    key, value = stripped.split('=', 2)
    return if key.nil? || value.nil? || key.strip.empty?

    key = key.strip
    return unless ENV[key].nil? || ENV[key].empty?

    ENV[key] = unquote_dotenv_value(value.strip)
  end

  def unquote_dotenv_value(value)
    return value[1..-2] if quoted_dotenv_value?(value)

    value
  end

  def quoted_dotenv_value?(value)
    value.length >= 2 && (
      (value.start_with?('"') && value.end_with?('"')) ||
        (value.start_with?("'") && value.end_with?("'"))
    )
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

  # CFBundleVersion / versionCode must keep rising across date-based marketing versions.
  def next_store_build_number(latest_store:, local_build: 0)
    [latest_store.to_i, local_build.to_i].max + 1
  end

  def unbundled_flutter_command(inner)
    unset = BUNDLER_ENV_UNSET_KEYS.map { |key| "-u #{key}" }.join(' ')
    "env #{unset} SKIP_VERSION_SYNC=1 #{inner}"
  end
end
