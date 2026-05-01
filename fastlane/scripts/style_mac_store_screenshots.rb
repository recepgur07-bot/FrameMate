#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"
require "tmpdir"

options = {
  input: nil,
  output: File.expand_path("../screenshots", __dir__),
  locales: "tr,en-US",
  copy: File.expand_path("mac_store_screenshot_copy.json", __dir__),
  screens: nil
}

OptionParser.new do |opts|
  opts.banner = "Usage: style_mac_store_screenshots.rb --input DIR [--output DIR] [--locales tr,en-US]"
  opts.on("--input DIR", "Raw screenshot directory") { |value| options[:input] = value }
  opts.on("--output DIR", "Output screenshot directory") { |value| options[:output] = value }
  opts.on("--locales LIST", "Comma-separated locales") { |value| options[:locales] = value }
  opts.on("--copy FILE", "Screenshot copy JSON") { |value| options[:copy] = value }
  opts.on("--screens LIST", "Optional comma-separated screen keys") { |value| options[:screens] = value }
end.parse!

def run_cmd!(*args)
  stdout, stderr, status = Open3.capture3(*args)
  return stdout if status.success?

  warn(stderr.empty? ? stdout : stderr)
  abort("Komut hatasi: #{args.join(' ')}")
end

def magick_bin
  @magick_bin ||= begin
    candidate = "/opt/homebrew/bin/magick"
    File.exist?(candidate) ? candidate : "magick"
  end
end

def escape_text(text)
  text.to_s.gsub("\\", "\\\\\\").gsub("'", "\\\\'")
end

def first_existing_font(paths, fallback)
  paths.find { |path| File.exist?(path) } || fallback
end

abort("--input gerekli") if options[:input].to_s.strip.empty?
abort("Girdi klasoru yok: #{options[:input]}") unless Dir.exist?(options[:input])
abort("Metin dosyasi yok: #{options[:copy]}") unless File.exist?(options[:copy])

run_cmd!(magick_bin, "-version")

copy = JSON.parse(File.read(options[:copy]))
canvas_width = copy.fetch("canvas").fetch("width")
canvas_height = copy.fetch("canvas").fetch("height")
screens = copy.fetch("screens")
if options[:screens]
  wanted = options[:screens].split(",").map(&:strip).reject(&:empty?)
  screens = screens.select { |screen| wanted.include?(screen.fetch("key")) }
  missing = wanted - screens.map { |screen| screen.fetch("key") }
  abort("Bilinmeyen ekran anahtari: #{missing.join(', ')}") unless missing.empty?
end
locales = options[:locales].split(",").map(&:strip).reject(&:empty?)

font_title = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
font_regular = "/System/Library/Fonts/Supplemental/Arial.ttf"

input_dir = File.expand_path(options[:input])
output_dir = File.expand_path(options[:output])

FileUtils.mkdir_p(output_dir)

generated = 0

locales.each do |locale|
  locale_dir = File.join(output_dir, locale)
  FileUtils.rm_rf(locale_dir)
  FileUtils.mkdir_p(locale_dir)

  screens.each do |screen|
    key = screen.fetch("key")
    localized = screen.fetch("locales").fetch(locale) do
      abort("Locale metni eksik: #{locale} / #{key}")
    end

    raw_path = Dir.glob(File.join(input_dir, "*#{key}*.png")).sort.first
    abort("Eksik ham ekran goruntusu: #{key} (#{input_dir})") if raw_path.nil?

    output_path = File.join(locale_dir, format("Mac-%s.png", key))
    sequence = key[/\A(\d{2})_/, 1] || "00"

    Dir.mktmpdir("framemate_store") do |tmp|
      background = File.join(tmp, "background.png")
      app_shot = File.join(tmp, "app.png")
      shadow = File.join(tmp, "shadow.png")
      title = File.join(tmp, "title.png")
      subtitle = File.join(tmp, "subtitle.png")
      badge = File.join(tmp, "badge.png")
      title_txt = File.join(tmp, "title.txt")
      subtitle_txt = File.join(tmp, "subtitle.txt")
      File.write(title_txt, localized.fetch('title'))
      File.write(subtitle_txt, localized.fetch('subtitle'))
      
      composed = File.join(tmp, "composed.png")
      run_cmd!(
        magick_bin,
        "-size", "#{canvas_width}x#{canvas_height}",
        "xc:#F6F8FB",
        "-fill", "#E7EDF6",
        "-draw", "rectangle 0,#{(canvas_height * 0.70).round} #{canvas_width},#{canvas_height}",
        "-fill", "#DDE7F5",
        "-draw", "circle #{(canvas_width * 0.88).round},#{(canvas_height * 0.13).round} #{(canvas_width * 1.03).round},#{(canvas_height * 0.13).round}",
        "-fill", "#E9F1EA",
        "-draw", "circle #{(canvas_width * 0.09).round},#{(canvas_height * 0.88).round} #{(canvas_width * 0.24).round},#{(canvas_height * 0.88).round}",
        background
      )

      run_cmd!(
        magick_bin,
        raw_path,
        "-resize", "2180x1226^",
        "-background", "white",
        "-gravity", "center",
        "-extent", "2180x1226",
        app_shot
      )

      run_cmd!(
        magick_bin,
        "-size", "2180x1226",
        "xc:none",
        "-fill", "rgba(22,34,52,0.24)",
        "-draw", "roundrectangle 0,0,2179,1225,34,34",
        "-blur", "0x28",
        shadow
      )

      run_cmd!(
        magick_bin,
        "-background", "none",
        "-fill", "#122033",
        "-font", font_title,
        "-pointsize", "92",
        "-size", "1760x260",
        "caption:@#{title_txt}",
        title
      )

      run_cmd!(
        magick_bin,
        "-background", "none",
        "-fill", "#42526A",
        "-font", font_regular,
        "-pointsize", "42",
        "-size", "1680x150",
        "caption:@#{subtitle_txt}",
        subtitle
      )

      run_cmd!(
        magick_bin,
        "-size", "280x72",
        "xc:none",
        "-fill", "#1F7A68",
        "-draw", "roundrectangle 0,0,279,71,24,24",
        "-fill", "white",
        "-font", font_title,
        "-pointsize", "30",
        "-gravity", "center",
        "-annotate", "+0+0", "FRAMEMATE #{sequence}",
        badge
      )

      run_cmd!(
        magick_bin,
        background,
        shadow,
        "-geometry", "+350+502",
        "-composite",
        app_shot,
        "-geometry", "+350+470",
        "-composite",
        badge,
        "-geometry", "+350+132",
        "-composite",
        title,
        "-geometry", "+350+220",
        "-composite",
        subtitle,
        "-geometry", "+350+388",
        "-composite",
        composed
      )

      run_cmd!(
        magick_bin,
        composed,
        "-strip",
        "-alpha", "remove",
        "-alpha", "off",
        output_path
      )
    end

    generated += 1
  end
end

puts "Olusturulan ekran goruntusu: #{generated}"
