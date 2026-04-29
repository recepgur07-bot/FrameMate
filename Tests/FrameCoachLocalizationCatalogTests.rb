# frozen_string_literal: true

require "json"
require "minitest/autorun"

class FrameCoachLocalizationCatalogTests < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CATALOG = File.join(ROOT, "Sources", "VideoRecorderApp", "Localizable.xcstrings")
  INFO_PLIST_CATALOG = File.join(ROOT, "Sources", "VideoRecorderApp", "InfoPlist.xcstrings")

  REQUIRED_FRAME_COACH_KEYS = [
    "Bir kişi görünüyor",
    "İki kişi görünüyor",
    "Üç kişi görünüyor",
    "Yüz algılanamıyor",
    "Yüz algılanamıyor, kameraya bak",
    "ışık düşük, lambayı aç veya ekran parlaklığını artır",
    "kadraj uygun",
    "kadraj dengeli",
    "kişi",
    "soldaki kişi",
    "ortadaki kişi",
    "sağdaki kişi",
    "Kadraja tam girmiyorsun, biraz sağa gel",
    "Kadraja tam girmiyorsun, biraz sola gel",
    "%@ kadraja tam girmiyor, biraz sağa gelsin",
    "%@ kadraja tam girmiyor, biraz sola gelsin",
    "%@ arkada kalmış, biraz yana açılsın",
    "%@ kameraya daha yakın, biraz geri gelsin",
    "%@ kadrajda çok aşağıda, biraz yukarı otursun",
    "%@ kadrajda çok yukarıda, biraz aşağı otursun",
    "çok yakınsın, biraz uzaklaş — omuzların ve göğsün de görünsün",
    "kadraj çok uzak, biraz yaklaş",
    "Çok uzaktasınız, ikiniz de biraz yaklaşın",
    "Çok uzaktasınız, hepiniz biraz yaklaşın",
    "aranız biraz açık, birbirinize yaklaşın",
    "aranız çok açık, birbirinize biraz yaklaşın",
    "grup çok açılmış, birbirinize biraz yaklaşın",
    "kamerayı belirgin şekilde yukarı al",
    "kamerayı biraz yukarı al",
    "kamerayı belirgin şekilde aşağı indir",
    "kamerayı biraz aşağı indir",
    "belirgin şekilde sağa geç",
    "biraz sağa geç",
    "grup çok solda kalmış, belirgin şekilde sağa kayın",
    "grup biraz solda kalmış, biraz sağa kayın",
    "belirgin şekilde sola geç",
    "biraz sola geç",
    "grup çok sağda kalmış, belirgin şekilde sola kayın",
    "grup biraz sağda kalmış, biraz sola kayın"
  ].freeze

  def test_frame_coach_live_guidance_has_english_and_turkish_strings
    strings = JSON.parse(File.read(CATALOG)).fetch("strings")

    missing = REQUIRED_FRAME_COACH_KEYS.flat_map do |key|
      entry = strings[key]
      if entry.nil?
        ["#{key}: missing key"]
      else
        %w[en tr].reject { |locale| entry.fetch("localizations", {}).key?(locale) }.map do |locale|
          "#{key}: missing #{locale}"
        end
      end
    end

    assert_empty missing
  end

  def test_app_localizable_catalog_has_english_and_turkish_for_every_key
    strings = JSON.parse(File.read(CATALOG)).fetch("strings")

    missing = strings.flat_map do |key, entry|
      missing_locales_for(key, entry)
    end

    assert_empty missing
  end

  def test_info_plist_catalog_has_english_and_turkish_for_every_key
    strings = JSON.parse(File.read(INFO_PLIST_CATALOG)).fetch("strings")

    missing = strings.flat_map do |key, entry|
      missing_locales_for(key, entry)
    end

    assert_empty missing
  end

  private

  def missing_locales_for(key, entry)
    localizations = entry.fetch("localizations", {})

    %w[en tr].each_with_object([]) do |locale, missing|
      value = localizations.dig(locale, "stringUnit", "value").to_s.strip
      missing << "#{key}: missing #{locale}" if value.empty?
    end
  end
end
