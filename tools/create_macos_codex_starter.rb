#!/opt/homebrew/bin/ruby
# frozen_string_literal: true

require "fileutils"
require "optparse"
require "open3"

def classify_name(value)
  parts = value.scan(/[A-Za-z0-9]+/)
  classified = parts.map { |part| part[0].upcase + part[1..].to_s }.join
  classified = "MacOSApp" if classified.empty?
  classified = "App#{classified}" if classified.match?(/\A[0-9]/)
  classified
end

def text_file?(path)
  text_extensions = %w[
    .md .toml .rb .swift .plist .xcprivacy .yml .yaml .json .txt .entitlements .gitignore
  ]
  text_extensions.include?(File.extname(path)) || File.basename(path) == ".gitignore"
end

options = {
  display_name: nil,
  output: nil,
  team_id: "",
  minimum_macos: "14.0",
  skip_xcodegen: false,
}

OptionParser.new do |parser|
  parser.banner = "Usage: create_macos_codex_starter.rb --name NAME --bundle-id BUNDLE_ID [options]"

  parser.on("--name NAME", "Module/project base name, e.g. LoomLite") do |value|
    options[:name] = value
  end

  parser.on("--display-name NAME", "Human-readable app name shown in the UI") do |value|
    options[:display_name] = value
  end

  parser.on("--bundle-id ID", "Bundle identifier, e.g. com.example.LoomLite") do |value|
    options[:bundle_id] = value
  end

  parser.on("--output PATH", "Output directory for the generated project") do |value|
    options[:output] = value
  end

  parser.on("--team-id ID", "Optional Apple development team ID") do |value|
    options[:team_id] = value
  end

  parser.on("--minimum-macos VERSION", "Deployment target, default 14.0") do |value|
    options[:minimum_macos] = value
  end

  parser.on("--skip-xcodegen", "Do not run xcodegen after generating files") do
    options[:skip_xcodegen] = true
  end
end.parse!

abort("Missing required option: --name") if options[:name].to_s.strip.empty?
abort("Missing required option: --bundle-id") if options[:bundle_id].to_s.strip.empty?

module_name = classify_name(options[:name])
display_name = options[:display_name].to_s.strip
display_name = options[:name] if display_name.empty?
output_path = options[:output] || File.join(Dir.pwd, module_name)
template_root = File.expand_path("../templates/apple-macos-codex-starter", __dir__)

abort("Template directory not found: #{template_root}") unless Dir.exist?(template_root)

if File.exist?(output_path) && !Dir.empty?(output_path)
  abort("Output directory already exists and is not empty: #{output_path}")
end

FileUtils.mkdir_p(output_path)

placeholder_map = {
  "__MODULE_NAME__" => module_name,
  "__DISPLAY_NAME__" => display_name,
  "__BUNDLE_IDENTIFIER__" => options[:bundle_id],
  "__TEAM_ID__" => options[:team_id],
  "__MINIMUM_MACOS__" => options[:minimum_macos],
  "__COPYRIGHT_YEAR__" => Time.now.year.to_s,
}

Dir.glob(File.join(template_root, "**", "*"), File::FNM_DOTMATCH).sort.each do |source_path|
  next if [".", ".."].include?(File.basename(source_path))

  relative_path = source_path.delete_prefix("#{template_root}/")
  destination_path = File.join(output_path, relative_path)

  if File.directory?(source_path)
    FileUtils.mkdir_p(destination_path)
    next
  end

  FileUtils.mkdir_p(File.dirname(destination_path))

  if text_file?(source_path)
    contents = File.read(source_path)
    placeholder_map.each do |key, value|
      contents = contents.gsub(key, value)
    end
    File.write(destination_path, contents)
  else
    FileUtils.cp(source_path, destination_path)
  end
end

unless options[:skip_xcodegen]
  xcodegen_command = if File.executable?("/opt/homebrew/bin/xcodegen")
    "/opt/homebrew/bin/xcodegen"
  else
    "xcodegen"
  end

  stdout, stderr, status = Open3.capture3(xcodegen_command, "generate", chdir: output_path)
  stdout = stdout.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
  stderr = stderr.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
  abort("xcodegen failed:\n#{stdout}\n#{stderr}") unless status.success?
  puts stdout unless stdout.strip.empty?
end

puts "Created macOS Codex starter at #{output_path}"
puts "Project file: #{File.join(output_path, "#{module_name}.xcodeproj")}" unless options[:skip_xcodegen]
