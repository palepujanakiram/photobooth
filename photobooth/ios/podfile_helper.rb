# frozen_string_literal: true

# Flutter root resolution for Podfile (keeps Podfile complexity low for Qlty metrics).
module PhotoboothPodfile
  module_function

  def flutter_root(podfile_dir)
    settings_path = File.expand_path(File.join('Flutter', 'Generated.xcconfig'), podfile_dir)
    raise_missing_settings(settings_path) unless File.exist?(settings_path)

    root = parse_flutter_root(settings_path)
    return root if root

    raise "FLUTTER_ROOT not found in #{settings_path}. " \
          'Try deleting Generated.xcconfig, then run flutter pub get'
  end

  def raise_missing_settings(settings_path)
    raise "#{settings_path} must exist. " \
          'If you\'re running pod install manually, make sure flutter pub get is executed first'
  end

  def parse_flutter_root(settings_path)
    File.foreach(settings_path) do |line|
      matches = line.match(/FLUTTER_ROOT=(.*)/)
      return matches[1].strip if matches
    end
    nil
  end
end
