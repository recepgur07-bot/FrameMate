# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "minitest/autorun"

class StoreScreenshotStylerTests < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "fastlane", "scripts", "style_mac_store_screenshots.rb")

  def test_generates_localized_mac_store_screenshots
    Dir.mktmpdir("framemate-screenshots") do |dir|
      raw_dir = File.join(dir, "raw")
      output_dir = File.join(dir, "out")
      FileUtils.mkdir_p(raw_dir)

      raw_path = File.join(raw_dir, "01_Record_Everything.png")
      run!("magick", "-size", "720x450", "gradient:#f8fafc-#dbeafe", raw_path)

      run!("ruby", SCRIPT, "--input", raw_dir, "--output", output_dir, "--locales", "tr,en-US", "--screens", "01_Record_Everything")

      tr_output = File.join(output_dir, "tr", "Mac-01_Record_Everything.png")
      en_output = File.join(output_dir, "en-US", "Mac-01_Record_Everything.png")

      assert File.exist?(tr_output), "expected #{tr_output} to exist"
      assert File.exist?(en_output), "expected #{en_output} to exist"
      assert_equal "2880 1800", identify_size(tr_output)
      assert_equal "2880 1800", identify_size(en_output)
    end
  end

  def test_fails_when_required_raw_screenshot_is_missing
    Dir.mktmpdir("framemate-screenshots") do |dir|
      raw_dir = File.join(dir, "raw")
      output_dir = File.join(dir, "out")
      FileUtils.mkdir_p(raw_dir)

      stdout, stderr, status = Open3.capture3("ruby", SCRIPT, "--input", raw_dir, "--output", output_dir, "--locales", "tr")

      refute status.success?, "expected missing raw screenshots to fail, stdout=#{stdout.inspect}"
      assert_includes stderr, "Eksik ham ekran goruntusu"
    end
  end

  def test_tall_raw_screenshots_fill_the_app_frame_without_side_margins
    Dir.mktmpdir("framemate-screenshots") do |dir|
      raw_dir = File.join(dir, "raw")
      output_dir = File.join(dir, "out")
      FileUtils.mkdir_p(raw_dir)

      raw_path = File.join(raw_dir, "01_Record_Everything.png")
      run!("magick", "-size", "720x1200", "xc:#3366CC", raw_path)

      run!("ruby", SCRIPT, "--input", raw_dir, "--output", output_dir, "--locales", "en-US", "--screens", "01_Record_Everything")

      en_output = File.join(output_dir, "en-US", "Mac-01_Record_Everything.png")
      assert_equal "#3366CC", pixel_color(en_output, 360, 900)
    end
  end

  private

  def run!(*args)
    stdout, stderr, status = Open3.capture3(*args)
    assert status.success?, "Command failed: #{args.join(" ")}\nSTDOUT: #{stdout}\nSTDERR: #{stderr}"
  end

  def identify_size(path)
    stdout, stderr, status = Open3.capture3("magick", "identify", "-format", "%w %h", path)
    assert status.success?, stderr
    stdout
  end

  def pixel_color(path, x, y)
    stdout, stderr, status = Open3.capture3("magick", path, "-format", "%[hex:p{#{x},#{y}}]", "info:")
    assert status.success?, stderr
    hex = stdout.strip
    hex = hex.scan(/..../).map { |channel| channel[0, 2] }.join if hex.length == 12
    "##{hex}"
  end
end
