#!/usr/bin/env ruby
# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require 'optparse'
require 'find'
require 'pathname'
require 'json'
require 'fileutils'
require 'rbconfig'
require 'rubygems'
require 'open3'

LAUNCH_SOURCE_FILENAMES = %w[AppDelegate.mm UnityAppController.mm AppController.mm].freeze

# Default minimum supported iOS version (IPHONEOS_DEPLOYMENT_TARGET).
# Override per run with --ios-min 14.0, or --set IPHONEOS_DEPLOYMENT_TARGET=14.0.
DEFAULT_IOS_DEPLOYMENT_TARGET = '13.0'

# Compilable source files: attached to the target's Sources (compile) phase.
SOURCE_CODE_EXTENSIONS = %w[.m .mm .c .cc .cpp .cxx .swift].freeze

# Header files: referenced but never attached to a build phase.
HEADER_EXTENSIONS = %w[.h .hh .hpp .hxx .pch].freeze

# Source files that must be skipped by the generic auto-attach: SDKMessager.mm
# (attached to the correct target by dedicated logic) and app launch sources
# (AppDelegate.mm etc.), to avoid compiling them into the wrong/duplicate target.
SPECIALLY_HANDLED_SOURCE_FILENAMES = (%w[SDKMessager.mm] + LAUNCH_SOURCE_FILENAMES).freeze

# Directory package suffixes whose contents are managed as a whole elsewhere
# (asset catalogs, localized folders, storyboards, frameworks/bundles) and must
# not be attached to the target file-by-file.
MANAGED_CONTAINER_SUFFIXES = %w[.xcassets .appiconset .lproj .storyboard .storyboardc .xcdatamodeld .framework .bundle].freeze

def ensure_xcodeproj_gem!
  activate = lambda do
    gem 'xcodeproj'
    require 'xcodeproj'
    true
  rescue Gem::LoadError, LoadError
    false
  end

  return if activate.call

  puts 'Dependency missing: xcodeproj. Installing...'

  ruby_exe = RbConfig.ruby
  installed = system(ruby_exe, '-S', 'gem', 'install', '--no-document', 'xcodeproj')
  unless installed
    puts 'Retrying with sudo. Please enter your password if prompted...'
    installed = system('sudo', ruby_exe, '-S', 'gem', 'install', '--no-document', 'xcodeproj')
  end
  unless installed
    puts 'Retrying with user gem installation...'
    installed = system(ruby_exe, '-S', 'gem', 'install', '--user-install', '--no-document', 'xcodeproj')
    if installed
      user_dir = Gem.user_dir
      ENV['GEM_HOME'] = user_dir if ENV['GEM_HOME'].to_s.empty?
      ENV['GEM_PATH'] = [user_dir, ENV['GEM_PATH']].compact.reject(&:empty?).join(File::PATH_SEPARATOR)
    end
  end

  unless installed
    puts "Error: failed to install gem xcodeproj with Ruby #{ruby_exe}."
    puts "Please run: sudo #{ruby_exe} -S gem install --no-document xcodeproj"
    exit 1
  end

  Gem.clear_paths
  unless activate.call
    puts 'Error: gem xcodeproj was installed but cannot be loaded in current Ruby environment.'
    puts "Ruby: #{ruby_exe}"
    puts "Gem paths: #{Gem.path.join(', ')}"
    puts 'Try running this script with the same Ruby that installed the gem.'
    exit 1
  end
end

ensure_xcodeproj_gem!

def excluded_import_path?(path)
  downcased = path.downcase
  return true if File.basename(downcased) == 'info.plist'
  return true if downcased.end_with?('.ds_store')

  path.split(File::SEPARATOR).any? { |segment| segment.downcase.end_with?('.dsym') }
end

def recursive_package_dir?(path)
  downcased = path.downcase
  downcased.end_with?('.framework') || downcased.end_with?('.bundle')
end

def package_file_type(path)
  downcased = path.downcase
  return 'wrapper.framework' if downcased.end_with?('.framework')
  return 'wrapper.plug-in' if downcased.end_with?('.bundle')

  nil
end

def ensure_file_in_phase(phase, file_ref)
  return false if phase.files_references.include?(file_ref)

  phase.add_file_reference(file_ref, true)
  true
end

def apply_build_setting(target_or_project, key, value)
  target_or_project.build_configurations.each do |config|
    config.build_settings[key] = value
  end
end

def apply_build_settings(target_or_project, settings)
  settings.each { |key, value| apply_build_setting(target_or_project, key, value) }
end

# Merge (append) values into an array-style build setting such as
# FRAMEWORK_SEARCH_PATHS for every build configuration, WITHOUT dropping the
# target's existing entries. Unlike apply_build_setting (which overwrites), this
# is safe for targets that already carry their own search paths (e.g. the
# Unity-generated UnityFramework target). '$(inherited)' is always kept/added and
# duplicates are avoided.
def append_build_setting_values(target_or_project, key, values)
  target_or_project.build_configurations.each do |config|
    current = config.build_settings[key]
    list = case current
           when nil then []
           when Array then current.dup
           else [current]
           end
    list.unshift('$(inherited)') unless list.include?('$(inherited)')
    Array(values).each { |value| list << value unless list.include?(value) }
    config.build_settings[key] = list
  end
end

def find_or_create_embed_frameworks_phase(target)
  phase = target.copy_files_build_phases.find do |p|
    p.name == 'Embed Frameworks' || p.symbol_dst_subfolder_spec == :frameworks
  end
  return phase if phase

  phase = target.new_copy_files_build_phase('Embed Frameworks')
  phase.symbol_dst_subfolder_spec = :frameworks
  phase
end

def ensure_embed_and_sign_framework(target, file_ref)
  embed_phase = find_or_create_embed_frameworks_phase(target)
  build_file = embed_phase.files.find { |f| f.file_ref == file_ref }
  changed = false

  unless build_file
    build_file = embed_phase.add_file_reference(file_ref, true)
    changed = true
  end

  settings = build_file.settings || {}
  attributes = Array(settings['ATTRIBUTES'])
  %w[CodeSignOnCopy RemoveHeadersOnCopy].each do |attr|
    next if attributes.include?(attr)

    attributes << attr
    changed = true
  end
  settings['ATTRIBUTES'] = attributes
  build_file.settings = settings

  changed
end

def ensure_link_framework(target, file_ref)
  ensure_file_in_phase(target.frameworks_build_phase, file_ref)
end

def ensure_source_in_target(target, file_ref)
  ensure_file_in_phase(target.source_build_phase, file_ref)
end

def attach_package_to_target(target, file_ref)
  type = file_ref.last_known_file_type
  added = false

  if type == 'wrapper.framework'
    linked = ensure_file_in_phase(target.frameworks_build_phase, file_ref)
    embedded = ensure_embed_and_sign_framework(target, file_ref)
    added = linked || embedded
  elsif type == 'wrapper.plug-in'
    added = ensure_file_in_phase(target.resources_build_phase, file_ref)
  end

  added
end

def within_managed_container?(path)
  path.split(File::SEPARATOR).any? do |segment|
    downcased = segment.downcase
    MANAGED_CONTAINER_SUFFIXES.any? { |suffix| downcased.end_with?(suffix) }
  end
end

# Attach a plain (non-package) file to the target: compilable source files go to
# the Sources (compile) phase, everything else goes to bundle resources. Headers,
# entitlements, files living inside managed containers (asset catalogs,
# storyboards, frameworks, etc.), and specially-handled sources are left alone.
def attach_regular_file_to_target(target, file_ref, absolute_path)
  return false if within_managed_container?(absolute_path)

  ext = File.extname(absolute_path).downcase
  return false if HEADER_EXTENSIONS.include?(ext)
  return false if ext == '.entitlements'

  if SOURCE_CODE_EXTENSIONS.include?(ext)
    return false if SPECIALLY_HANDLED_SOURCE_FILENAMES.include?(File.basename(absolute_path))

    return ensure_source_in_target(target, file_ref)
  end

  ensure_file_in_phase(target.resources_build_phase, file_ref)
end

def find_file_reference_by_absolute_path(project, absolute_path)
  normalized_path = File.expand_path(absolute_path)
  project.files.find do |file_ref|
    begin
      File.expand_path(file_ref.real_path.to_s) == normalized_path
    rescue StandardError
      false
    end
  end
end

def resolved_file_ref_path(file_ref)
  File.expand_path(file_ref.real_path.to_s)
rescue StandardError
  nil
end

def upsert_file_reference(group, absolute_path, display_name, file_type = nil)
  existing = group.files.find { |ref| ref.display_name == display_name }
  if existing
    return [existing, :skipped] if resolved_file_ref_path(existing) == File.expand_path(absolute_path)

    existing.remove_from_project
    created = group.new_file(absolute_path, :absolute)
    created.name = display_name
    created.last_known_file_type = file_type if file_type
    return [created, :repaired]
  end

  created = group.new_file(absolute_path, :absolute)
  created.name = display_name
  created.last_known_file_type = file_type if file_type
  [created, :added]
end

def find_or_create_group(parent_group, name)
  parent_group.groups.find { |g| g.path == name || g.display_name == name } || parent_group.new_group(name)
end

def find_or_create_subgroup(root_group, relative_dir)
  return root_group if relative_dir.nil? || relative_dir == '.'

  relative_dir.split(File::SEPARATOR).reject(&:empty?).inject(root_group) do |group, segment|
    find_or_create_group(group, segment)
  end
end

def file_reference_exists?(project, absolute_path)
  normalized_path = File.expand_path(absolute_path)
  project.files.any? do |file_ref|
    begin
      File.expand_path(file_ref.real_path.to_s) == normalized_path
    rescue StandardError
      false
    end
  end
end

def path_under_directory?(path, directory)
  normalized_path = File.expand_path(path)
  normalized_directory = File.expand_path(directory)
  normalized_path == normalized_directory || normalized_path.start_with?("#{normalized_directory}/")
end

def relative_path_from_project_root(project_path, absolute_path)
  project_root = File.dirname(File.expand_path(project_path))
  Pathname.new(File.expand_path(absolute_path)).relative_path_from(Pathname.new(project_root)).to_s
end

def pick_info_plist_for_packages(directory_path)
  absolute_dir = File.expand_path(directory_path)
  candidate_files = []

  Find.find(absolute_dir) do |entry|
    next unless File.directory?(entry)
    next if excluded_import_path?(entry)

    children = Dir.children(entry)
    has_package = children.any? do |name|
      child_path = File.join(entry, name)
      File.directory?(child_path) && recursive_package_dir?(child_path)
    end
    next unless has_package

    info_name = children.find { |name| name.downcase == 'info.plist' }
    next unless info_name

    candidate_files << File.join(entry, info_name)
  rescue SystemCallError
    next
  end

  candidate_files.uniq.sort
end

def apply_target_infoplist(target, plist_path)
  apply_build_setting(target, 'INFOPLIST_FILE', plist_path)
end

def project_root_from_xcodeproj(project_path)
  File.dirname(File.expand_path(project_path))
end

def read_plist_as_hash(plist_path)
  stdout, stderr, status = Open3.capture3('plutil', '-convert', 'json', '-o', '-', plist_path)
  raise "Failed to parse plist '#{plist_path}': #{stderr}".strip unless status.success?

  JSON.parse(stdout)
end

def load_team_id_from_directory(directory_path)
  plist_path = File.join(File.expand_path(directory_path), 'Info.plist')
  return nil unless File.exist?(plist_path)

  plist_hash = read_plist_as_hash(plist_path)
  team_id = plist_hash['teamid']
  return nil if team_id.nil?

  team_id = team_id.to_s.strip
  team_id.empty? ? nil : team_id
end

def load_bundle_id_from_directory(directory_path)
  plist_path = File.join(File.expand_path(directory_path), 'Info.plist')
  return nil unless File.exist?(plist_path)

  plist_hash = read_plist_as_hash(plist_path)
  bundle_id = plist_hash['CFBundleIdentifier'] || plist_hash['bundleid'] || plist_hash['bundleId']
  return nil if bundle_id.nil?

  bundle_id = bundle_id.to_s.strip
  return nil if bundle_id.empty?
  return nil if bundle_id.match?(/\$\(/)

  bundle_id
end

def apply_target_bundle_identifier(target, bundle_id)
  apply_build_setting(target, 'PRODUCT_BUNDLE_IDENTIFIER', bundle_id)
end

def apply_bundle_identifier_from_plist(project, target, directory_path)
  bundle_id = load_bundle_id_from_directory(directory_path)
  return nil unless bundle_id

  apply_target = detect_target_by_name(project, 'Unity-iPhone') || target
  apply_target_bundle_identifier(apply_target, bundle_id)
  bundle_id
end

def pick_assets_catalog(project_root)
  existing = Dir.glob(File.join(project_root, '**', '*.xcassets')).sort
  return existing.find { |p| File.directory?(File.join(p, 'AppIcon.appiconset')) } if existing.any? { |p| File.directory?(File.join(p, 'AppIcon.appiconset')) }
  return existing.first unless existing.empty?

  File.join(project_root, 'Assets.xcassets')
end

# Remove the project's built-in "Images.xcassets" (references + on-disk folder).
# Called when the SDK add-dir ships its own 1024.png so the vendor icon catalog
# does not conflict/duplicate with the app's built-in asset catalog.
def remove_bundled_images_xcassets(project, project_root, catalog_name = 'Images.xcassets')
  removed_build_files = 0
  removed_file_refs = 0
  removed_groups = 0
  deleted_paths = []

  matches_catalog = lambda do |obj|
    names = []
    names << obj.display_name.to_s if obj.respond_to?(:display_name)
    names << File.basename(obj.name.to_s) if obj.respond_to?(:name) && obj.name
    names << File.basename(obj.path.to_s) if obj.respond_to?(:path) && obj.path
    names.include?(catalog_name)
  end

  project.targets.each do |t|
    next unless t.respond_to?(:resources_build_phase) && t.resources_build_phase

    t.resources_build_phase.files.dup.each do |build_file|
      file_ref = build_file.file_ref
      next unless file_ref && matches_catalog.call(file_ref)

      build_file.remove_from_project
      removed_build_files += 1
    end
  end

  project.files.dup.each do |file_ref|
    next unless matches_catalog.call(file_ref)

    resolved = resolved_file_ref_path(file_ref)
    deleted_paths << resolved if resolved
    file_ref.remove_from_project
    removed_file_refs += 1
  end

  project.objects.select { |obj| obj.isa == 'PBXGroup' }.each do |group|
    next unless matches_catalog.call(group)

    resolved = begin
      File.expand_path(group.real_path.to_s)
    rescue StandardError
      nil
    end
    deleted_paths << resolved if resolved
    group.remove_from_project
    removed_groups += 1
  end

  disk_candidates = deleted_paths.compact
  disk_candidates += Dir.glob(File.join(File.expand_path(project_root), '**', catalog_name))
  disk_candidates = disk_candidates.map { |p| File.expand_path(p) }.uniq
  disk_candidates.each do |path|
    next unless File.basename(path) == catalog_name && Dir.exist?(path)

    FileUtils.rm_rf(path)
    deleted_paths << path
  end

  {
    removed_build_files: removed_build_files,
    removed_file_refs: removed_file_refs,
    removed_groups: removed_groups,
    deleted_paths: deleted_paths.compact.uniq
  }
end

def find_icon_source_png(directory_path)
  exact = File.join(File.expand_path(directory_path), '1024.png')
  return exact if File.exist?(exact)

  candidates = Dir.glob(File.join(File.expand_path(directory_path), '**', '1024.png')).sort
  candidates.first
end

def app_icon_spec
  [
    { idiom: 'iphone', size: '20x20', scale: '2x' },
    { idiom: 'iphone', size: '20x20', scale: '3x' },
    { idiom: 'iphone', size: '29x29', scale: '2x' },
    { idiom: 'iphone', size: '29x29', scale: '3x' },
    { idiom: 'iphone', size: '40x40', scale: '2x' },
    { idiom: 'iphone', size: '40x40', scale: '3x' },
    { idiom: 'iphone', size: '60x60', scale: '2x' },
    { idiom: 'iphone', size: '60x60', scale: '3x' },
    { idiom: 'ipad', size: '20x20', scale: '1x' },
    { idiom: 'ipad', size: '20x20', scale: '2x' },
    { idiom: 'ipad', size: '29x29', scale: '1x' },
    { idiom: 'ipad', size: '29x29', scale: '2x' },
    { idiom: 'ipad', size: '40x40', scale: '1x' },
    { idiom: 'ipad', size: '40x40', scale: '2x' },
    { idiom: 'ipad', size: '76x76', scale: '1x' },
    { idiom: 'ipad', size: '76x76', scale: '2x' },
    { idiom: 'ipad', size: '83.5x83.5', scale: '2x' },
    { idiom: 'ios-marketing', size: '1024x1024', scale: '1x' }
  ]
end

def find_icon_template_json(project_root, source_png_path, icon_name)
  source_dir = File.dirname(File.expand_path(source_png_path))
  search_roots = [
    project_root,
    source_dir,
    File.dirname(source_dir)
  ].uniq.select { |path| Dir.exist?(path) }

  direct_candidates = search_roots.map do |root|
    File.join(root, 'Images.xcassets', "#{icon_name}.appiconset", 'Contents.json')
  end
  direct_candidates.find { |path| File.file?(path) } ||
    search_roots.lazy.flat_map do |root|
      Dir.glob(File.join(root, '**', "#{icon_name}.appiconset", 'Contents.json')).sort
    end.find { |path| File.file?(path) }
end

def load_icon_template_images(template_json_path = nil)
  if template_json_path && File.exist?(template_json_path)
    begin
      data = JSON.parse(File.read(template_json_path))
      images = Array(data['images'])
      return images if images.any?
    rescue JSON::ParserError
      # Fall back to built-in spec below when template is invalid.
    end
  end

  app_icon_spec.map do |item|
    px = pixel_size(item[:size], item[:scale])
    {
      'idiom' => item[:idiom],
      'size' => item[:size],
      'scale' => item[:scale],
      'expected-size' => px.to_s,
      'filename' => "#{px}.png",
      'folder' => 'Assets.xcassets/AppIcon.appiconset/'
    }
  end
end

def pixel_size(size_text, scale_text)
  base = size_text.split('x').first.to_f
  scale = scale_text.delete('x').to_i
  (base * scale).round
end

def create_app_icon_assets(project_path, source_png_path, icon_name = 'AppIcon')
  project_root = project_root_from_xcodeproj(project_path)
  xcassets_path = pick_assets_catalog(project_root)
  appiconset_path = File.join(xcassets_path, "#{icon_name}.appiconset")
  template_json_path = File.join(appiconset_path, 'Contents.json')
  template_json_path = find_icon_template_json(project_root, source_png_path, icon_name) unless File.file?(template_json_path)
  template_images = load_icon_template_images(template_json_path)

  # Recreate icon set directory to avoid stale/broken generated files.
  FileUtils.rm_rf(appiconset_path)
  FileUtils.mkdir_p(appiconset_path)

  generated_sizes_by_filename = {}

  template_images.each do |item|
    next unless item['filename']

    filename = item['filename']
    px = item['expected-size'].to_s.strip.to_i
    px = pixel_size(item['size'].to_s, item['scale'].to_s) if px <= 0 && item['size'] && item['scale']
    if px <= 0
      inferred = File.basename(filename, '.png').to_i
      px = inferred if inferred.positive?
    end
    next if px <= 0

    if generated_sizes_by_filename.key?(filename)
      next if generated_sizes_by_filename[filename] == px

      raise "Conflicting icon size for #{filename}: #{generated_sizes_by_filename[filename]} vs #{px}"
    end
    generated_sizes_by_filename[filename] = px

    output_path = File.join(appiconset_path, filename)
    success = system('sips', '-z', px.to_s, px.to_s, source_png_path, '--out', output_path, out: File::NULL, err: File::NULL)
    unless success
      raise "Failed to generate icon #{filename} from #{source_png_path}"
    end
  end

  contents = {
    'images' => template_images,
    'info' => {
      'version' => 1,
      'author' => 'xcode'
    }
  }
  File.write(File.join(appiconset_path, 'Contents.json'), JSON.pretty_generate(contents))

  [xcassets_path, appiconset_path]
end

def apply_target_app_icon_name(target, icon_name)
  apply_build_setting(target, 'ASSETCATALOG_COMPILER_APPICON_NAME', icon_name)
end

def apply_target_launch_storyboard_name(target, storyboard_name)
  apply_build_setting(target, 'ASSETCATALOG_COMPILER_LAUNCHSTORYBOARD_NAME', storyboard_name)
  apply_build_setting(target, 'INFOPLIST_KEY_UILaunchStoryboardName', storyboard_name)
end

def find_launch_storyboard_path(sdk_directory)
  direct = File.join(File.expand_path(sdk_directory), 'LaunchScreen.storyboard')
  return direct if File.file?(direct)

  candidates = Dir.glob(File.join(File.expand_path(sdk_directory), '**', 'LaunchScreen.storyboard')).sort
  candidates.first
end

def storyboard_file_ref?(file_ref, storyboard_name)
  [file_ref.display_name, file_ref.name, file_ref.path].compact.any? do |name|
    File.basename(name.to_s) == storyboard_name
  end
end

def named_file_ref?(file_ref, file_name)
  [file_ref.display_name, file_ref.name, file_ref.path].compact.any? do |name|
    File.basename(name.to_s) == file_name
  end
end

def ensure_launch_storyboard_reference(project, target, storyboard_path)
  normalized = File.expand_path(storyboard_path)
  sdk_directory = File.dirname(normalized)
  storyboard_name = File.basename(normalized)
  background_name = 'LaunchScreenBackground.png'
  storyboard_ref = find_file_reference_by_absolute_path(project, normalized)
  background_path = File.join(sdk_directory, background_name)
  background_ref = File.file?(background_path) ? find_file_reference_by_absolute_path(project, background_path) : nil

  unless storyboard_ref
    storyboard_ref = project.main_group.new_file(normalized, :absolute)
    storyboard_ref.name = storyboard_name
  end
  storyboard_ref.last_known_file_type = 'file.storyboard'

  if File.file?(background_path) && background_ref.nil?
    background_ref = project.main_group.new_file(background_path, :absolute)
    background_ref.name = background_name
  end
  background_ref.last_known_file_type = 'image.png' if background_ref

  removed_build_files = 0
  removed_file_refs = 0
  target.resources_build_phase.files.dup.each do |build_file|
    file_ref = build_file.file_ref
    next unless file_ref

    resolved = resolved_file_ref_path(file_ref)
    remove_storyboard = storyboard_file_ref?(file_ref, storyboard_name) && resolved != normalized
    remove_background = named_file_ref?(file_ref, background_name) && resolved != background_path
    next unless remove_storyboard || remove_background

    build_file.remove_from_project
    removed_build_files += 1
  end

  project.files.dup.each do |file_ref|
    next if file_ref == storyboard_ref || file_ref == background_ref

    resolved = resolved_file_ref_path(file_ref)
    remove_storyboard = storyboard_file_ref?(file_ref, storyboard_name) && resolved != normalized
    remove_background = named_file_ref?(file_ref, background_name) && resolved != background_path
    next unless remove_storyboard || remove_background

    file_ref.remove_from_project
    removed_file_refs += 1
  end

  attached = ensure_file_in_phase(target.resources_build_phase, storyboard_ref)
  background_attached = background_ref ? ensure_file_in_phase(target.resources_build_phase, background_ref) : nil
  launch_name = File.basename(storyboard_name, '.storyboard')
  apply_target_launch_storyboard_name(target, launch_name)

  {
    path: normalized,
    attached: attached,
    background_path: File.file?(background_path) ? background_path : nil,
    background_attached: background_attached,
    launch_name: launch_name,
    removed_build_files: removed_build_files,
    removed_file_refs: removed_file_refs
  }
end

def apply_target_code_sign_entitlements(target, entitlements_path)
  apply_build_setting(target, 'CODE_SIGN_ENTITLEMENTS', entitlements_path)
end

# Copy the whole <PROJECT>.xcodeproj directory to <PROJECT>.xcodeproj.bak-<timestamp>
# (same parent directory) before the script modifies anything. The backup name does
# not end with .xcodeproj, so Xcode and the auto-detect glob ignore it.
# Returns the backup path, or nil when the .xcodeproj directory does not exist.
BACKUP_TIMESTAMP = Time.now.strftime('%Y%m%d-%H%M%S')

def backup_xcodeproj(xcodeproj_path)
  source = File.expand_path(xcodeproj_path.to_s.chomp('/'))
  return nil unless File.directory?(source)

  backup = "#{source}.bak-#{BACKUP_TIMESTAMP}"
  FileUtils.rm_rf(backup)
  FileUtils.cp_r(source, backup, preserve: true)
  puts "Backed up #{File.basename(source)} -> #{backup}"
  backup
end

def detect_xcodeproj_in_script_dir
  candidates = Dir.glob(File.join(__dir__, '*.xcodeproj')).sort
  return [nil, 'No .xcodeproj found in script directory.'] if candidates.empty?
  return [nil, "Multiple .xcodeproj found in script directory: #{candidates.map { |p| File.basename(p) }.join(', ')}"] if candidates.size > 1

  [candidates.first, nil]
end

def detect_executable_target(project)
  app_targets = project.targets.select { |t| t.respond_to?(:product_type) && t.product_type == 'com.apple.product-type.application' }
  return [nil, 'No executable application target found in project.'] if app_targets.empty?

  # Only iPhone/iPad app targets are candidates: a Cocos project also has a
  # "-desktop" macOS app target, which sorts before "-mobile" alphabetically.
  ios_app_targets = app_targets.select { |t| ios_target?(project, t) }
  if ios_app_targets.empty?
    return [nil, "No iOS application target found. Application targets: #{app_targets.map(&:name).sort.join(', ')}"]
  end

  # Prefer names that clearly mean the phone build (e.g. "MergeCook-mobile", "Unity-iPhone").
  sorted = ios_app_targets.sort_by do |t|
    mobile_hint = t.name =~ /mobile|iphone|ios/i ? 0 : 1
    [mobile_hint, t.name]
  end
  selected = sorted.first
  warning = nil
  if sorted.length > 1
    warning = "Multiple iOS executable targets found: #{sorted.map(&:name).join(', ')}. Auto-selected '#{selected.name}'."
  end
  [selected, warning]
end

def detect_target_by_name(project, name)
  project.targets.find { |target| target.name == name }
end

# Resolve a build setting for a target configuration, falling back to the
# project-level configuration with the same name (targets usually inherit
# SDKROOT / SUPPORTED_PLATFORMS from the project).
def resolve_config_setting(project, config, key)
  value = config.build_settings[key]
  return value unless value.nil?

  project_config = project.build_configuration_list.build_configurations.find { |c| c.name == config.name }
  project_config && project_config.build_settings[key]
end

# True when the target builds for iPhone/iPad (iphoneos SDK). macOS / tvOS /
# watchOS / visionOS targets are skipped so their own deployment target keys
# are left untouched.
def ios_target?(project, target)
  return false unless target.respond_to?(:build_configurations)

  platform = begin
    target.platform_name
  rescue StandardError
    nil
  end
  return true if platform == :ios
  return false if [:osx, :tvos, :watchos, :visionos].include?(platform)

  target.build_configurations.any? do |config|
    sdkroot = resolve_config_setting(project, config, 'SDKROOT').to_s
    supported = Array(resolve_config_setting(project, config, 'SUPPORTED_PLATFORMS')).join(' ')
    sdkroot.include?('iphoneos') ||
      supported.include?('iphoneos') ||
      config.build_settings.key?('IPHONEOS_DEPLOYMENT_TARGET')
  end
end

def ios_targets(project)
  project.targets.select { |t| ios_target?(project, t) }
end

# Apply IPHONEOS_DEPLOYMENT_TARGET to every iPhone/iPad target in the project so
# app, framework and extension targets share the same minimum iOS version.
# Project-level configs are only updated when they already define the key.
def apply_deployment_target_to_ios_targets(project, version)
  targets = ios_targets(project)
  targets.each { |t| apply_build_setting(t, 'IPHONEOS_DEPLOYMENT_TARGET', version) }
  project.build_configurations.each do |config|
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = version if config.build_settings.key?('IPHONEOS_DEPLOYMENT_TARGET')
  end
  targets.map(&:name)
end

# Absolute paths of sub-projects (*.xcodeproj file references) embedded in the
# project, e.g. cocos2d_libs.xcodeproj referenced by a Cocos main project.
def subproject_paths(project)
  paths = []
  project.objects.each do |obj|
    next unless obj.is_a?(Xcodeproj::Project::Object::PBXFileReference)
    next unless obj.path.to_s.end_with?('.xcodeproj')

    real = begin
      obj.real_path.to_s
    rescue StandardError
      nil
    end
    paths << File.expand_path(real) if real && File.directory?(real)
  end
  paths.uniq
end

# Recursively apply IPHONEOS_DEPLOYMENT_TARGET to the iOS targets of every
# sub-project (and their sub-projects). Each changed sub-project is saved.
# Returns [{ path:, targets: [names] }].
def apply_deployment_target_to_subprojects(project, version, visited = {})
  results = []
  visited[File.expand_path(project.path.to_s)] = true
  subproject_paths(project).each do |sub_path|
    next if visited[sub_path]

    visited[sub_path] = true
    begin
      sub_project = Xcodeproj::Project.open(sub_path)
    rescue StandardError => e
      puts "Warning: failed to open sub-project #{sub_path}: #{e.message}"
      next
    end
    names = apply_deployment_target_to_ios_targets(sub_project, version)
    sub_project.save
    results << { path: sub_path, targets: names }
    results.concat(apply_deployment_target_to_subprojects(sub_project, version, visited))
  end
  results
end

def unity_framework_file_ref?(file_ref)
  [file_ref.display_name, file_ref.name, file_ref.path].compact.any? do |name|
    File.basename(name.to_s) == 'UnityFramework.framework'
  end
end

def unity_framework_linked_in_target?(target)
  target.frameworks_build_phase.files_references.any? { |file_ref| unity_framework_file_ref?(file_ref) }
end

# Ensure Unity-iPhone links UnityFramework.framework in "Link Binary With Libraries".
# Some SDK integrations leave the app target with only Embed Frameworks configured.
def ensure_unity_framework_linked_in_unity_iphone(project, unity_iphone_target_name = 'Unity-iPhone')
  unity_iphone_target = detect_target_by_name(project, unity_iphone_target_name)
  unless unity_iphone_target
    return {
      found: false,
      reason: "target '#{unity_iphone_target_name}' not found"
    }
  end

  unity_framework_target = detect_target_by_name(project, 'UnityFramework')
  unless unity_framework_target
    return {
      found: false,
      reason: 'UnityFramework target not found'
    }
  end

  framework_ref = unity_framework_target.product_reference
  unless framework_ref
    return {
      found: false,
      reason: 'UnityFramework product reference not found'
    }
  end

  if unity_framework_linked_in_target?(unity_iphone_target)
    return {
      found: true,
      target_name: unity_iphone_target_name,
      already_linked: true,
      linked: false
    }
  end

  linked = ensure_link_framework(unity_iphone_target, framework_ref)
  {
    found: true,
    target_name: unity_iphone_target_name,
    already_linked: false,
    linked: linked
  }
end

def find_sdkmessager_source_path(sdk_directory)
  absolute_sdk_dir = File.expand_path(sdk_directory)
  direct = File.join(absolute_sdk_dir, 'SDKMessager.mm')
  return direct if File.exist?(direct)

  candidates = Dir.glob(File.join(absolute_sdk_dir, '**', 'SDKMessager.mm')).sort
  candidates.first
end

def attach_unityframework_dependencies(project, unity_target, sdk_directory)
  absolute_sdk_dir = File.expand_path(sdk_directory)
  framework_path = File.join(absolute_sdk_dir, 'AppSDK.framework')
  source_path = find_sdkmessager_source_path(absolute_sdk_dir) || File.join(absolute_sdk_dir, 'SDKMessager.mm')

  framework_ref = File.exist?(framework_path) ? find_file_reference_by_absolute_path(project, framework_path) : nil
  source_ref = File.exist?(source_path) ? find_file_reference_by_absolute_path(project, source_path) : nil

  framework_attached = framework_ref ? ensure_link_framework(unity_target, framework_ref) : nil
  source_attached = source_ref ? ensure_source_in_target(unity_target, source_ref) : nil

  {
    framework_path: framework_path,
    source_path: source_path,
    framework_found: !framework_ref.nil?,
    source_found: !source_ref.nil?,
    framework_attached: framework_attached,
    source_attached: source_attached
  }
end

# When a UnityFramework target links AppSDK, the main app must still embed a copy
# of AppSDK.framework and re-sign it with the app's identity. Otherwise the copy
# left in the bundle keeps the vendor's signature and iOS Library Validation
# rejects it at load time ("code signature ... not valid for use in process").
# This mirrors adding AppSDK.framework to the main target's
# "Frameworks, Libraries, and Embedded Content" as Embed & Sign.
def ensure_appsdk_embed_and_sign_in_target(project, target, sdk_directory)
  absolute_sdk_dir = File.expand_path(sdk_directory)
  framework_path = File.join(absolute_sdk_dir, 'AppSDK.framework')
  framework_ref = File.exist?(framework_path) ? find_file_reference_by_absolute_path(project, framework_path) : nil

  unless framework_ref
    return {
      framework_path: framework_path,
      framework_found: false,
      linked: nil,
      embedded: nil
    }
  end

  linked = ensure_link_framework(target, framework_ref)
  embedded = ensure_embed_and_sign_framework(target, framework_ref)

  {
    framework_path: framework_path,
    framework_found: true,
    linked: linked,
    embedded: embedded
  }
end

def attach_main_target_sources(project, main_target, sdk_directory)
  absolute_sdk_dir = File.expand_path(sdk_directory)
  source_path = find_sdkmessager_source_path(absolute_sdk_dir) || File.join(absolute_sdk_dir, 'SDKMessager.mm')
  source_ref = File.exist?(source_path) ? find_file_reference_by_absolute_path(project, source_path) : nil
  source_attached = source_ref ? ensure_source_in_target(main_target, source_ref) : nil

  {
    source_path: source_path,
    source_found: !source_ref.nil?,
    source_attached: source_attached
  }
end

def ensure_xcassets_reference_and_attach(project, target, xcassets_path)
  normalized = File.expand_path(xcassets_path)
  existing = project.files.find do |file_ref|
    begin
      File.expand_path(file_ref.real_path.to_s) == normalized
    rescue StandardError
      false
    end
  end

  file_ref = existing
  unless file_ref
    file_ref = project.main_group.new_file(normalized, :absolute)
    file_ref.last_known_file_type = 'folder.assetcatalog'
    file_ref.name = File.basename(normalized)
  end

  ensure_file_in_phase(target.resources_build_phase, file_ref)
end

def cleanup_existing_directory_references(project, directory_path)
  absolute_dir = File.expand_path(directory_path)
  removed_file_refs = 0
  removed_groups = 0

  # Remove file references that point to the same directory tree.
  project.files.each do |file_ref|
    begin
      resolved = File.expand_path(file_ref.real_path.to_s)
    rescue StandardError
      next
    end
    next unless path_under_directory?(resolved, absolute_dir)

    file_ref.remove_from_project
    removed_file_refs += 1
  end

  # Remove root import groups created for this absolute directory.
  project.main_group.groups.dup.each do |group|
    next unless group.source_tree == '<absolute>'
    next unless group.path && File.expand_path(group.path) == absolute_dir

    group.remove_from_project
    removed_groups += 1
  end

  [removed_file_refs, removed_groups]
end

def add_directory_references(project, target, directory_path, excluded_package_names_for_target = [])
  absolute_dir = File.expand_path(directory_path)
  excluded_package_names = excluded_package_names_for_target.map(&:downcase)
  import_group_name = File.basename(absolute_dir)
  import_group = project.main_group.groups.find do |group|
    group.display_name == import_group_name &&
      group.source_tree == '<absolute>' &&
      group.path == absolute_dir
  end
  import_group ||= project.main_group.new_group(import_group_name, absolute_dir, :absolute)
  imported_count = 0
  skipped_count = 0
  package_dir_count = 0
  repaired_count = 0
  target_attached_count = 0

  Find.find(absolute_dir) do |entry|
    if File.directory?(entry)
      if excluded_import_path?(entry)
        skipped_count += 1
        Find.prune
      end

      if recursive_package_dir?(entry)
        package_dir_count += 1
        relative_to_import_dir = entry.delete_prefix("#{absolute_dir}/")
        subgroup_relative_dir = File.dirname(relative_to_import_dir)
        subgroup = find_or_create_subgroup(import_group, subgroup_relative_dir)
        package_name = File.basename(entry)
        should_attach_to_target = !excluded_package_names.include?(package_name.downcase)

        package_ref, status = upsert_file_reference(subgroup, entry, package_name, package_file_type(entry))
        if status == :skipped
          target_attached_count += 1 if should_attach_to_target && attach_package_to_target(target, package_ref)
          skipped_count += 1
          Find.prune
          next
        end
        repaired_count += 1 if status == :repaired
        target_attached_count += 1 if should_attach_to_target && attach_package_to_target(target, package_ref)
        imported_count += 1
        Find.prune
        next
      end

      next
    end

    if excluded_import_path?(entry)
      skipped_count += 1
      next
    end

    if file_reference_exists?(project, entry)
      existing_ref = find_file_reference_by_absolute_path(project, entry)
      target_attached_count += 1 if existing_ref && attach_regular_file_to_target(target, existing_ref, entry)
      skipped_count += 1
      next
    end

    relative_to_import_dir = entry.delete_prefix("#{absolute_dir}/")
    subgroup_relative_dir = File.dirname(relative_to_import_dir)
    subgroup = find_or_create_subgroup(import_group, subgroup_relative_dir)
    file_ref, status = upsert_file_reference(subgroup, entry, File.basename(entry))
    if status == :skipped
      target_attached_count += 1 if attach_regular_file_to_target(target, file_ref, entry)
      skipped_count += 1
      next
    end
    repaired_count += 1 if status == :repaired
    target_attached_count += 1 if attach_regular_file_to_target(target, file_ref, entry)
    imported_count += 1
  end

  [imported_count, skipped_count, package_dir_count, repaired_count, target_attached_count]
end

def infer_hortor_directory_from_reference(hortor_ref)
  return nil unless hortor_ref
  return File.expand_path(hortor_ref.real_path.to_s) if hortor_ref.respond_to?(:real_path) && Dir.exist?(File.expand_path(hortor_ref.real_path.to_s))

  if hortor_ref.isa == 'PBXGroup'
    child_file = hortor_ref.files.find do |file_ref|
      resolved = resolved_file_ref_path(file_ref)
      resolved && File.exist?(resolved)
    end
    return File.dirname(resolved_file_ref_path(child_file)) if child_file
  end

  nil
end

def ensure_blue_folder_reference(parent_group, folder_name, absolute_path)
  existing_children = parent_group.children.select do |child|
    display = child.respond_to?(:display_name) ? child.display_name : nil
    child_path = child.respond_to?(:path) ? child.path.to_s : ''
    display == folder_name || File.basename(child_path) == folder_name
  end
  existing_children.each(&:remove_from_project)

  folder_ref = parent_group.new_file(folder_name)
  folder_ref.name = folder_name
  folder_ref.source_tree = '<group>'
  folder_ref.explicit_file_type = nil
  folder_ref.last_known_file_type = 'folder'
  [folder_ref, existing_children.empty? ? :added : :recreated]
end

def target_resources_group(project, target)
  target_group = project.objects.select { |obj| obj.isa == 'PBXGroup' }.find { |group| group.display_name == target.name }
  return nil unless target_group

  target_group.groups.find { |group| group.display_name == 'Resources' }
end

def visible_resources_group_for_hortor(project, target, folder_names)
  target_group_resources = target_resources_group(project, target)
  return target_group_resources if target_group_resources

  resource_groups = project.objects.select { |obj| obj.isa == 'PBXGroup' && obj.display_name == 'Resources' }

  group_with_old_yellow_folders = resource_groups.find do |group|
    group.children.any? do |child|
      next false unless child.isa == 'PBXGroup'

      display = child.respond_to?(:display_name) ? child.display_name.to_s : child.name.to_s
      path_base = File.basename(child.path.to_s)
      folder_names.include?(display) || folder_names.include?(path_base)
    end
  end
  return group_with_old_yellow_folders if group_with_old_yellow_folders

  resource_groups.find do |group|
    next false unless group.display_name == 'Resources'

    child_names = group.children.map do |child|
      display = child.respond_to?(:display_name) ? child.display_name.to_s : child.name.to_s
      path_base = File.basename(child.path.to_s)
      display.empty? ? path_base : display
    end
    (child_names & folder_names).any?
  end
end

def remove_existing_resource_folder_refs(project, target, folder_names)
  target.resources_build_phase.files.dup.each do |build_file|
    file_ref = build_file.file_ref
    next unless file_ref

    display = file_ref.respond_to?(:display_name) ? file_ref.display_name.to_s : file_ref.name.to_s
    path_base = File.basename(file_ref.path.to_s)
    next unless folder_names.include?(display) || folder_names.include?(path_base)

    build_file.remove_from_project
  end

  project.objects.select { |obj| obj.isa == 'PBXGroup' && obj.display_name == 'Resources' }.each do |group|
    group.children.dup.each do |child|
      display = child.respond_to?(:display_name) ? child.display_name.to_s : child.name.to_s
      path_base = File.basename(child.path.to_s)
      next unless folder_names.include?(display) || folder_names.include?(path_base)

      group.children.delete(child)
      child.remove_from_project if %w[PBXGroup PBXFileReference].include?(child.isa)
    end
  end
end

def find_group_in_tree(group, name)
  return group if group.display_name == name || group.path == name

  group.groups.each do |child|
    found = find_group_in_tree(child, name)
    return found if found
  end
  nil
end

def sync_hortor_sibling_blue_folders(project, target)
  folder_names = %w[jsb-adapter assets src hortor]
  candidates = project.objects.select { |obj| %w[PBXGroup PBXFileReference].include?(obj.isa) }
  named_hortor_refs = candidates.select do |obj|
    display = obj.respond_to?(:display_name) ? obj.display_name.to_s : obj.name.to_s
    path_base = File.basename(obj.path.to_s)
    display == 'hortor' || path_base == 'hortor'
  end

  path_hortor_dirs = project.files.map do |file_ref|
    path = file_ref.path.to_s
    next nil unless path.include?('/hortor/')

    File.dirname(path)
  end.compact

  inferred_dirs = named_hortor_refs.map { |ref| infer_hortor_directory_from_reference(ref) }.compact
  all_hortor_dirs = (inferred_dirs + path_hortor_dirs).uniq

  hortor_dir = all_hortor_dirs.max_by do |dir|
    base = File.dirname(File.expand_path(dir))
    folder_names.count { |name| Dir.exist?(File.join(base, name)) }
  end
  return { found: false } unless hortor_dir

  selected_ref = named_hortor_refs.find { |ref| infer_hortor_directory_from_reference(ref) == hortor_dir }
  parent_group = visible_resources_group_for_hortor(project, target, folder_names)
  parent_group ||= selected_ref ? project.objects.select { |obj| obj.isa == 'PBXGroup' }.find { |group| group.children.include?(selected_ref) } : nil
  parent_group ||= find_group_in_tree(project.main_group, 'Resources')
  parent_group ||= project.main_group

  siblings_base_dir = File.dirname(hortor_dir)
  parent_group_base = begin
    parent_group.parent.real_path
  rescue StandardError
    Pathname.new(File.dirname(project.path.to_s))
  end
  parent_group.path = Pathname.new(File.expand_path(siblings_base_dir)).relative_path_from(parent_group_base).to_s
  parent_group.source_tree = '<group>'
  remove_existing_resource_folder_refs(project, target, folder_names)
  results = []

  folder_names.each do |folder_name|
    absolute_path = File.join(siblings_base_dir, folder_name)
    next unless Dir.exist?(absolute_path)

    folder_ref, status = ensure_blue_folder_reference(parent_group, folder_name, absolute_path)
    attached = ensure_file_in_phase(target.resources_build_phase, folder_ref)
    results << {
      name: folder_name,
      path: absolute_path,
      status: status,
      attached: attached
    }
  end

  {
    found: true,
    base_dir: siblings_base_dir,
    results: results
  }
end

def cleanup_legacy_copy_files_phases(target)
  prefixes = ['assets/', 'src/', 'hortor/', 'jsb-adapter/']
  removed_phase_count = 0
  removed_file_count = 0

  target.copy_files_build_phases.dup.each do |phase|
    next if phase.name == 'Embed App Extensions' || phase.name == 'Embed Frameworks'
    next unless phase.dst_subfolder_spec.to_s == '7'

    phase_files = phase.files.to_a
    next if phase_files.empty?

    dst_path = phase.dst_path.to_s
    matches_by_dst = prefixes.any? { |prefix| dst_path.start_with?(prefix) }
    matches_by_file = phase_files.any? do |build_file|
      file_path = build_file.file_ref&.path.to_s
      prefixes.any? { |prefix| file_path.include?("/#{prefix}") || file_path.start_with?(prefix) }
    end

    next unless matches_by_dst || matches_by_file

    removed_file_count += phase_files.size
    phase.remove_from_project
    removed_phase_count += 1
  end

  {
    removed_phase_count: removed_phase_count,
    removed_file_count: removed_file_count
  }
end

if ARGV.include?('-h') || ARGV.include?('--help')
  puts 'Usage: ruby update_build_settings.rb [PROJECT.xcodeproj] [TARGET_NAME] [options]'
  puts ''
  puts 'Options:'
  puts '  --include-project             Also update project-level build settings'
  puts '  --set KEY=VALUE               Override/add a string build setting (repeatable)'
  puts '  --set-array KEY=v1,v2,v3      Override/add an array build setting (repeatable)'
  puts '  --append KEY=v1,v2,v3         Append values to a build setting, keeping existing ones (repeatable)'
  puts '  --add-dir DIR                 Recursively add directory files as xcodeproj references'
  puts '  --Asset                       Add jsb-adapter/assets/src/hortor as blue folder references'
  puts "  --ios-min VERSION             Minimum supported iOS version for ALL iPhone targets (default #{DEFAULT_IOS_DEPLOYMENT_TARGET})"
  puts ''
  puts 'Examples:'
  puts '  ruby update_build_settings.rb'
  puts '  ruby update_build_settings.rb Runner'
  puts '  ruby update_build_settings.rb ./App.xcodeproj'
  puts '  ruby update_build_settings.rb ./App.xcodeproj Runner'
  puts '  ruby update_build_settings.rb ./App.xcodeproj Runner --set ENABLE_BITCODE=YES'
  puts '  ruby update_build_settings.rb ./App.xcodeproj Runner --set DEVELOPMENT_TEAM=ABCDE12345'
  puts '  ruby update_build_settings.rb ./App.xcodeproj Runner --set-array LD_RUNPATH_SEARCH_PATHS="$(inherited),@executable_path/Frameworks"'
  puts '  ruby update_build_settings.rb ./App.xcodeproj Runner --append OTHER_LDFLAGS="-ObjC,-lz"'
  puts '  ruby update_build_settings.rb ./App.xcodeproj Runner --add-dir ./ios/Runner/Assets'
  puts '  ruby update_build_settings.rb ./App.xcodeproj Runner --add-dir ./ios/sdk --ios-min 14.0'
  exit 0
end

default_build_settings = {
  'IPHONEOS_DEPLOYMENT_TARGET' => DEFAULT_IOS_DEPLOYMENT_TARGET,
  'ENABLE_BITCODE' => 'NO',
  'GCC_GENERATE_DEBUGGING_SYMBOLS' => 'Yes',
  'TARGETED_DEVICE_FAMILY' => '1,2',
  'SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD' => 'NO',
  'CODE_SIGN_IDENTITY' => 'Apple Development',
  'CODE_SIGN_STYLE' => 'Automatic',
  'DEVELOPMENT_TEAM' => 'NY8F98XKT6',
  'LD_RUNPATH_SEARCH_PATHS' => [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@loader_path/Frameworks'
  ]
}

include_project = false
custom_build_settings = {}
# KEY => [values] collected from --append. Applied AFTER the overwrite settings
# above, so existing values (and any --set/--set-array/default value) are kept.
append_build_settings = {}
add_dir = nil
sync_hortor_blue_folders = false
remaining_args = ARGV.dup

option_parser = OptionParser.new do |opts|
  opts.on('--include-project', 'Also update project-level build settings') do
    include_project = true
  end

  opts.on('--set KEY=VALUE', 'Override/add a string build setting (repeatable)') do |pair|
    key, value = pair.split('=', 2)
    if key.nil? || key.empty? || value.nil?
      puts "Error: invalid --set '#{pair}'. Expected KEY=VALUE."
      exit 1
    end
    custom_build_settings[key] = value
  end

  opts.on('--set-array KEY=v1,v2,v3', 'Override/add an array build setting (repeatable)') do |pair|
    key, value = pair.split('=', 2)
    if key.nil? || key.empty? || value.nil?
      puts "Error: invalid --set-array '#{pair}'. Expected KEY=v1,v2,v3."
      exit 1
    end
    values = value.split(',').map(&:strip).reject(&:empty?)
    custom_build_settings[key] = values
  end

  opts.on('--append KEY=v1,v2,v3', 'Append values to a build setting, keeping existing ones (repeatable)') do |pair|
    key, value = pair.split('=', 2)
    if key.nil? || key.empty? || value.nil?
      puts "Error: invalid --append '#{pair}'. Expected KEY=v1,v2,v3."
      exit 1
    end
    values = value.split(',').map(&:strip).reject(&:empty?)
    if values.empty?
      puts "Error: --append '#{pair}' has no values."
      exit 1
    end
    append_build_settings[key] ||= []
    values.each { |v| append_build_settings[key] << v unless append_build_settings[key].include?(v) }
  end

  opts.on('--add-dir DIR', 'Recursively add directory files as xcodeproj references') do |dir|
    add_dir = dir
  end

  opts.on('--Asset', 'Add jsb-adapter/assets/src/hortor as blue folder references') do
    sync_hortor_blue_folders = true
  end

  opts.on('--ios-min VERSION', "Minimum supported iOS version (default #{DEFAULT_IOS_DEPLOYMENT_TARGET})") do |version|
    value = version.to_s.strip
    unless value.match?(/\A\d+(\.\d+){0,2}\z/)
      puts "Error: invalid --ios-min '#{version}'. Expected a version like 13.0."
      exit 1
    end
    custom_build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = value
  end
end

begin
  option_parser.parse!(remaining_args)
rescue OptionParser::ParseError => e
  puts "Error: #{e.message}"
  exit 1
end

puts 'Tip: pass --Asset to add jsb-adapter/assets/src/hortor as blue folder references; omitted by default.'

if add_dir.nil? || add_dir.strip.empty?
  puts 'Error: missing required option --add-dir DIR.'
  puts 'Usage: ruby update_build_settings.rb [PROJECT.xcodeproj] [TARGET_NAME] --add-dir DIR [options]'
  exit 1
end

project_path = nil
target_name = nil

if remaining_args.length > 2
  puts "Error: too many positional arguments: #{remaining_args.join(' ')}"
  puts 'Usage: ruby update_build_settings.rb [PROJECT.xcodeproj] [TARGET_NAME] [options]'
  exit 1
elsif remaining_args.length == 2
  project_path = remaining_args[0]
  target_name = remaining_args[1]
elsif remaining_args.length == 1
  if remaining_args[0].end_with?('.xcodeproj')
    project_path = remaining_args[0]
  else
    target_name = remaining_args[0]
  end
end

if project_path.nil?
  project_path, detect_error = detect_xcodeproj_in_script_dir
  if detect_error
    puts "Error: #{detect_error}"
    puts 'Please pass the .xcodeproj path explicitly.'
    exit 1
  end
  puts "Auto-detected project: #{project_path}"
end

unless File.exist?(project_path) && project_path.end_with?('.xcodeproj')
  puts "Error: invalid .xcodeproj path: #{project_path}"
  exit 1
end

# Derive FRAMEWORK_SEARCH_PATHS from the directory passed via --add-dir instead of
# hardcoding a fixed folder. Use a $(SRCROOT)-relative path for project portability.
framework_search_relative = relative_path_from_project_root(project_path, add_dir)
default_build_settings['FRAMEWORK_SEARCH_PATHS'] = [
  '$(inherited)',
  "$(SRCROOT)/#{framework_search_relative}"
]

# Use DEVELOPMENT_TEAM from the passed-in directory's Info.plist when a 'teamid'
# key is present; otherwise keep the built-in default above.
development_team_from_plist = load_team_id_from_directory(add_dir)
if development_team_from_plist
  default_build_settings['DEVELOPMENT_TEAM'] = development_team_from_plist
  puts "Using DEVELOPMENT_TEAM from #{File.join(File.expand_path(add_dir), 'Info.plist')} (teamid): #{development_team_from_plist}"
end

final_build_settings = default_build_settings.merge(custom_build_settings)

# Back up the whole .xcodeproj before any modification.
project_backup_path = backup_xcodeproj(project_path)

project = Xcodeproj::Project.open(project_path)

if include_project
  apply_build_settings(project, final_build_settings)
  append_build_settings.each { |key, values| append_build_setting_values(project, key, values) }
end

if target_name.nil?
  target, detect_warning = detect_executable_target(project)
  if target.nil?
    available_targets = project.targets.map(&:name).uniq.sort
    puts 'Error: no executable target could be auto-detected.'
    puts "Available targets: #{available_targets.join(', ')}"
    exit 1
  end
  target_name = target.name
  puts "Auto-detected target: #{target_name}"
  puts detect_warning if detect_warning
else
  target = project.targets.find { |t| t.name == target_name }
  if target.nil?
    available_targets = project.targets.map(&:name).uniq.sort
    puts "Error: target '#{target_name}' not found."
    puts "Available targets: #{available_targets.join(', ')}"
    exit 1
  end
end

# Update only the specified target build configurations.
apply_build_settings(target, final_build_settings)
# Then append (non-destructive) values requested via --append.
append_build_settings.each { |key, values| append_build_setting_values(target, key, values) }

# IPHONEOS_DEPLOYMENT_TARGET (from --ios-min / --set, or DEFAULT_IOS_DEPLOYMENT_TARGET
# when not passed) is applied to ALL iPhone targets, not only the selected one.
ios_deployment_target_names = apply_deployment_target_to_ios_targets(
  project, final_build_settings['IPHONEOS_DEPLOYMENT_TARGET']
)
# Sub-projects referenced by the main project (e.g. cocos2d_libs.xcodeproj ->
# libcocos2d iOS) build their own targets, so update them too.
subproject_deployment_results = apply_deployment_target_to_subprojects(
  project, final_build_settings['IPHONEOS_DEPLOYMENT_TARGET']
)

imported_count = 0
skipped_count = 0
package_dir_count = 0
repaired_count = 0
removed_file_refs = 0
removed_groups = 0
target_attached_count = 0
infoplist_relative_path = nil
bundle_identifier_from_plist = nil
app_icon_source_path = nil
app_icon_set_path = nil
images_xcassets_removal = nil
launch_storyboard_path = nil
launch_storyboard_result = nil
code_sign_entitlements_path = nil
unityframework_result = nil
unity_framework_search_path_applied = nil
hortor_sync_result = nil
legacy_copy_cleanup_result = nil
main_target_source_result = nil
main_target_appsdk_embed_result = nil
unity_iphone_framework_link_result = nil
main_target_excluded_package_names = []

if add_dir
  unless Dir.exist?(add_dir)
    puts "Error: --add-dir directory not found: #{add_dir}"
    exit 1
  end

  unity_target = detect_target_by_name(project, 'UnityFramework')
  main_target_excluded_package_names = ['AppSDK.framework'] if unity_target

  removed_file_refs, removed_groups = cleanup_existing_directory_references(project, add_dir)
  imported_count, skipped_count, package_dir_count, repaired_count, target_attached_count =
    add_directory_references(project, target, add_dir, main_target_excluded_package_names)

  plist_candidates = pick_info_plist_for_packages(add_dir)
  if plist_candidates.any?
    selected_plist = plist_candidates.find { |p| File.dirname(File.expand_path(p)) == File.expand_path(add_dir) } || plist_candidates.first
    infoplist_relative_path = relative_path_from_project_root(project_path, selected_plist)
    apply_target_infoplist(target, infoplist_relative_path)
  end

  bundle_identifier_from_plist = apply_bundle_identifier_from_plist(project, target, add_dir)

  app_icon_source_path = find_icon_source_png(add_dir)
  if app_icon_source_path
    # The SDK directory ships its own 1024.png, so drop the app's built-in
    # Images.xcassets (refs + on-disk folder) before generating the icon set to
    # avoid a duplicate/conflicting asset catalog. Must run before
    # create_app_icon_assets, which globs *.xcassets on disk to choose a catalog.
    images_xcassets_removal = remove_bundled_images_xcassets(project, project_root_from_xcodeproj(project_path))
    xcassets_path, app_icon_set_path = create_app_icon_assets(project_path, app_icon_source_path, 'AppIcon')
    ensure_xcassets_reference_and_attach(project, target, xcassets_path)
    apply_target_app_icon_name(target, 'AppIcon')
  end

  launch_storyboard_path = find_launch_storyboard_path(add_dir)
  launch_storyboard_result = ensure_launch_storyboard_reference(project, target, launch_storyboard_path) if launch_storyboard_path

  entitlements_absolute_path = File.join(File.expand_path(add_dir), 'sdk.entitlements')
  # Only set CODE_SIGN_ENTITLEMENTS when the SDK directory actually ships sdk.entitlements;
  # otherwise leave the target's existing setting untouched.
  if File.file?(entitlements_absolute_path)
    code_sign_entitlements_path = relative_path_from_project_root(project_path, entitlements_absolute_path)
    apply_target_code_sign_entitlements(target, code_sign_entitlements_path)
  end


  main_target_source_result = attach_main_target_sources(project, target, add_dir) unless unity_target
  if unity_target
    unityframework_result = attach_unityframework_dependencies(project, unity_target, add_dir)
    # UnityFramework links AppSDK.framework (above), so it must also be able to
    # locate it at compile/link time. Mirror the main target by adding the SDK
    # directory to UnityFramework's FRAMEWORK_SEARCH_PATHS using the same
    # $(SRCROOT)-relative path. Append (don't overwrite) so UnityFramework's own
    # Unity-generated search paths are preserved.
    append_build_setting_values(unity_target, 'FRAMEWORK_SEARCH_PATHS', "$(SRCROOT)/#{framework_search_relative}")
    # Keep the framework target's minimum iOS version in sync with the app target,
    # otherwise Xcode warns that the embedded framework targets a different OS.
    apply_build_setting(unity_target, 'IPHONEOS_DEPLOYMENT_TARGET', final_build_settings['IPHONEOS_DEPLOYMENT_TARGET'])
    unity_framework_search_path_applied = "$(SRCROOT)/#{framework_search_relative}"
    # AppSDK is excluded from the main target's auto-attach loop above, so embed &
    # sign it explicitly here to ensure the bundled copy is re-signed by the app.
    main_target_appsdk_embed_result = ensure_appsdk_embed_and_sign_in_target(project, target, add_dir)
    unity_iphone_framework_link_result = ensure_unity_framework_linked_in_unity_iphone(project)
  end
  if sync_hortor_blue_folders
    hortor_sync_result = sync_hortor_sibling_blue_folders(project, target)
    legacy_copy_cleanup_result = cleanup_legacy_copy_files_phases(target)
  end
end

project.save

if include_project
  puts "Updated build settings for target '#{target_name}' and project: #{project_path}"
else
  puts "Updated build settings for target '#{target_name}': #{project_path}"
end
if project_backup_path
  puts "Backup: #{project_backup_path}"
  restore_target = File.expand_path(project_path.to_s.chomp('/'))
  puts "  To undo: rm -rf \"#{restore_target}\" && cp -R \"#{project_backup_path}\" \"#{restore_target}\""
end
puts "Minimum supported iOS version (IPHONEOS_DEPLOYMENT_TARGET): #{final_build_settings['IPHONEOS_DEPLOYMENT_TARGET']}"
puts "Applied IPHONEOS_DEPLOYMENT_TARGET to iOS targets: #{ios_deployment_target_names.join(', ')}"
subproject_deployment_results.each do |r|
  puts "Applied IPHONEOS_DEPLOYMENT_TARGET to sub-project #{File.basename(r[:path])} iOS targets: #{r[:targets].join(', ')}"
end
append_build_settings.each do |key, values|
  puts "Appended to #{key}: #{values.join(', ')}"
end

if add_dir
  puts "Removed old references for '#{add_dir}': files=#{removed_file_refs}, groups=#{removed_groups}"
  puts "Imported references from '#{add_dir}': added=#{imported_count}, skipped=#{skipped_count}, repaired=#{repaired_count}"
  puts "Package references added for (.framework/.bundle): #{package_dir_count}"
  puts "Package references attached to target '#{target_name}': #{target_attached_count}"
  if main_target_excluded_package_names.any?
    puts "Excluded from target '#{target_name}' auto-attach loop because UnityFramework exists (handled explicitly with Embed & Sign): #{main_target_excluded_package_names.join(', ')}"
  end
  if bundle_identifier_from_plist
    bundle_target_name = detect_target_by_name(project, 'Unity-iPhone')&.name || target_name
    puts "Set target '#{bundle_target_name}' PRODUCT_BUNDLE_IDENTIFIER from Info.plist (CFBundleIdentifier): #{bundle_identifier_from_plist}"
  else
    puts "No concrete CFBundleIdentifier found in #{File.join(File.expand_path(add_dir), 'Info.plist')}, skipped Bundle Identifier override."
  end
  if infoplist_relative_path
    puts "Set target '#{target_name}' INFOPLIST_FILE: #{infoplist_relative_path}"
  else
    puts "No sibling Info.plist found for package directories under '#{add_dir}'."
  end
  if images_xcassets_removal
    puts "Removed built-in Images.xcassets (1024.png present in '#{add_dir}'): " \
         "build_files=#{images_xcassets_removal[:removed_build_files]}, " \
         "file_refs=#{images_xcassets_removal[:removed_file_refs]}, " \
         "groups=#{images_xcassets_removal[:removed_groups]}"
    if images_xcassets_removal[:deleted_paths].any?
      puts "Deleted Images.xcassets folders on disk: #{images_xcassets_removal[:deleted_paths].join(', ')}"
    end
  end
  if app_icon_set_path
    puts "Generated App Icon set from '#{app_icon_source_path}': #{app_icon_set_path}"
    puts "Set target '#{target_name}' ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon"
  else
    puts "No 1024.png found under '#{add_dir}', skipped App Icon generation."
  end
  if launch_storyboard_result
    storyboard_status = launch_storyboard_result[:attached] ? 'added to Resources' : 'already in Resources'
    puts "SDK LaunchScreen.storyboard: #{storyboard_status} (#{launch_storyboard_result[:path]})"
    if launch_storyboard_result[:background_path]
      background_status = launch_storyboard_result[:background_attached] ? 'added to Resources' : 'already in Resources'
      puts "SDK LaunchScreenBackground.png: #{background_status} (#{launch_storyboard_result[:background_path]})"
    else
      puts "No SDK LaunchScreenBackground.png found next to LaunchScreen.storyboard."
    end
    puts "Set target '#{target_name}' launch storyboard: #{launch_storyboard_result[:launch_name]}"
    puts "Removed existing non-SDK LaunchScreen.storyboard references: build_files=#{launch_storyboard_result[:removed_build_files]}, file_refs=#{launch_storyboard_result[:removed_file_refs]}"
  else
    puts "No LaunchScreen.storyboard found under '#{add_dir}', skipped launch storyboard replacement."
  end
  if main_target_source_result
    if main_target_source_result[:source_found]
      source_status = main_target_source_result[:source_attached] ? 'added to Sources' : 'already in Sources'
      puts "Main target SDKMessager.mm: #{source_status} (#{main_target_source_result[:source_path]})"
    else
      puts "Main target SDKMessager.mm: not found at #{main_target_source_result[:source_path]}"
    end
  end
  if unityframework_result
    puts "UnityFramework target detected."
    if unityframework_result[:framework_found]
      framework_status = unityframework_result[:framework_attached] ? 'linked' : 'already linked'
      puts "UnityFramework AppSDK.framework: #{framework_status} (#{unityframework_result[:framework_path]})"
    else
      puts "UnityFramework AppSDK.framework: not found at #{unityframework_result[:framework_path]}"
    end

    if unityframework_result[:source_found]
      source_status = unityframework_result[:source_attached] ? 'added to Sources' : 'already in Sources'
      puts "UnityFramework SDKMessager.mm: #{source_status} (#{unityframework_result[:source_path]})"
    else
      puts "UnityFramework SDKMessager.mm: not found at #{unityframework_result[:source_path]}"
    end

    if unity_framework_search_path_applied
      puts "UnityFramework FRAMEWORK_SEARCH_PATHS: added #{unity_framework_search_path_applied}"
    end
  end
  if unity_iphone_framework_link_result
    if !unity_iphone_framework_link_result[:found]
      puts "Unity-iPhone UnityFramework.framework: skipped (#{unity_iphone_framework_link_result[:reason]})"
    elsif unity_iphone_framework_link_result[:already_linked]
      puts "Unity-iPhone UnityFramework.framework: already linked in Link Binary With Libraries"
    else
      link_status = unity_iphone_framework_link_result[:linked] ? 'added to Link Binary With Libraries' : 'already in Link Binary With Libraries'
      puts "Unity-iPhone UnityFramework.framework: #{link_status}"
    end
  end
  if main_target_appsdk_embed_result
    if main_target_appsdk_embed_result[:framework_found]
      link_status = main_target_appsdk_embed_result[:linked] ? 'linked' : 'already linked'
      embed_status = main_target_appsdk_embed_result[:embedded] ? 'embedded & signed' : 'already embedded & signed'
      puts "Main target '#{target_name}' AppSDK.framework: #{link_status}, #{embed_status} (#{main_target_appsdk_embed_result[:framework_path]})"
    else
      puts "Main target '#{target_name}' AppSDK.framework: not found at #{main_target_appsdk_embed_result[:framework_path]}"
    end
  end
  if code_sign_entitlements_path
    puts "Set target '#{target_name}' CODE_SIGN_ENTITLEMENTS: #{code_sign_entitlements_path}"
  else
    puts "Skipped CODE_SIGN_ENTITLEMENTS: sdk.entitlements not found in #{File.expand_path(add_dir)}"
  end
  if !sync_hortor_blue_folders
    puts 'Skipped hortor sibling blue-folder sync: pass --Asset to enable.'
  elsif hortor_sync_result && hortor_sync_result[:found]
    puts "Synced blue folder references near hortor: base=#{hortor_sync_result[:base_dir]}"
    hortor_sync_result[:results].each do |entry|
      attach_status = entry[:attached] ? 'added to Resources' : 'already in Resources'
      puts "  - #{entry[:name]} => #{entry[:status]}, #{attach_status} (#{entry[:path]})"
    end
  else
    puts 'Skipped hortor sibling blue-folder sync: hortor reference not found.'
  end
  if legacy_copy_cleanup_result
    puts "Removed legacy gray Copy Files phases: phases=#{legacy_copy_cleanup_result[:removed_phase_count]}, files=#{legacy_copy_cleanup_result[:removed_file_count]}"
  end
  puts 'Skipped files include existing references and paths ending with .plist, .ds_store, or .dsym.'
end
