#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'date'
require 'json'
require 'nokogiri'
require 'open-uri'
require 'scraped'
require 'scraperwiki'
require 'uri'

POMBOLA_ID_TO_ID = {
  'core_person:680' => 'gov:victor-okezie-ikpeazu',
  'core_person:252' => 'gov:jibrilla-bindow',
  'core_person:681' => 'gov:emmanuel-udom',
  'core_person:532' => 'gov:willie-obiano',
  'core_person:682' => 'gov:barrister-mohammed-abubakar',
  'core_person:479' => 'gov:seriake-dickson',
  'core_person:683' => 'gov:samuel-ortom',
  'core_person:481' => 'gov:kashim-shettima',
  'core_person:98' => 'gov:ben-ayade',
  'core_person:90' => 'gov:senator-ifeanyi-okowa',
  'core_person:684' => 'gov:dave-umahi',
  # '' => 'gov:godwin-obaseki', Missing from Pombola
  'core_person:571' => 'gov:ayo-fayose',
  'core_person:431' => 'gov:ifeanyi-ugwuanyi',
  'core_person:488' => 'gov:ibrahim-dankwambo',
  'core_person:516' => 'gov:chief-rochas-okorocha',
  'core_person:685' => 'gov:alhaji-badaru-abubakar',
  'core_person:687' => 'gov:mallam-nasir-el-rufai',
  'core_person:686' => 'gov:umar-danguje',
  'core_person:688' => 'gov:aminu-masari',
  'core_person:108' => 'gov:atiku-bagudu',
  'core_person:939' => 'gov:yahaya-bello',
  'core_person:519' => 'gov:abdulfatah-ahmed',
  'core_person:572' => 'gov:ambode-akinwunmi',
  'core_person:498' => 'gov:umaru-tanko-al-makura',
  'core_person:689' => 'gov:alhaji-abubakar-sani-lulu-bello',
  'core_person:523' => 'gov:ibikunle-amosun',
  # '' => 'gov:oluwarontimi-akeredolu', Missing from Pombola
  'core_person:522' => 'gov:abiola-ajimobi',
  'core_person:524' => 'gov:rauf-aregbesola',
  'core_person:690' => 'gov:simon-lalong',
  'core_person:691' => 'gov:nyesom-wike',
  'core_person:453' => 'gov:aminu-waziri-tambuwal',
  'core_person:692' => 'gov:darius-ishaku',
  'core_person:508' => 'gov:ibrahim-geidam',
  'core_person:509' => 'gov:abdulaziz-abubakar-yari'
}

KNOWN_CONTACT_TYPES = [
  'email', 'phone', 'twitter', 'facebook', 'website'
].to_set

# From: http://stackoverflow.com/a/22994329/223092
VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i

TWITTER_USERNAME_REGEX = /\A@?(\w{1,15})\z/

VALID_URL_REGEX = /\A#{URI::regexp(['http', 'https'])}\z/

class String
  def titleize
    split(/(\W)/).map(&:capitalize).join
  end

  def tidy
    gsub(/[[:space:]]+/, ' ').strip
  end

  def slugify
    tidy.downcase.gsub(' ', '-').gsub(/[^\w-]/, '')
  end
end

class Governor < Scraped::HTML
  field :honorific_prefix do
    noko.css('td')[3].text.split('.')[0...-1].join.titleize.tidy
  end

  field :name do
    noko.css('td')[3].text.split('.')[-1].titleize.tidy
  end

  field :id do
    "gov:#{name.slugify}"
  end

  field :state do
    noko.css('td')[1].text.titleize.tidy
  end

  field :party do
    noko.css('td')[4].text.tidy
  end

  # Get extra fields from the Pombola data, if present:

  field :email do
    pombola_contact_details_of_type('email')
  end

  field :phone do
    pombola_contact_details_of_type('phone')
  end

  field :twitter do
    pombola_contact_details_of_type('twitter')
  end

  field :facebook_url do
    pombola_contact_details_of_type('facebook')
  end

  field :birth_date do
    pombola_data['birth_date']
  end

  field :gender do
    pombola_data['gender']
  end

  field :identifier__shineyoureye do
    identifiers = pombola_data.fetch('identifiers', [])
    identifier = identifiers.find { |i| i['scheme'] == 'pombola-slug' }
    identifier ? identifier['identifier'] : ''
  end

  field :image_url do
    image_urls = pombola_data.fetch('images', []).map { |i| i['url'] }
    first_image_url = image_urls.first
    return '' unless first_image_url
    first_image_url.gsub(/www\.shineyoureye\.org/, 'pombola.shineyoureye.org')
  end

  field :website_url do
    pombola_contact_details_of_type('website')
  end

  field :other_names do
    pombola_name = pombola_data.fetch('name', '').tidy
    if pombola_name.downcase == name.downcase
      ''
    else
      pombola_name
    end
  end

  private

  def id_to_pombola_data
    @@id_to_pombola_data ||= begin
      url = 'http://pombola.shineyoureye.org/media_root/popolo_json/persons.json'
      popolo = JSON.parse(open(url, &:read))
      only_known = popolo.select { |h| POMBOLA_ID_TO_ID[h['id']] }
      only_known.map { |h| [POMBOLA_ID_TO_ID[h['id']], h] }.to_h
    end
  end

  def pombola_data
    id_to_pombola_data.fetch(id, {})
  end

  def pombola_contact_details
    pombola_data.fetch('contact_details', [])
  end

  def pombola_contact_details_of_type(type)
    unless KNOWN_CONTACT_TYPES.include?(type)
      raise RuntimeError, "Unknown contact type #{type}"
    end
    cds = pombola_contact_details.find_all { |cd| cd['type'] == type }
    values = cds.map { |cd| cd['value'] }
    # Some values are comma-separated, so flatten those out:
    values = values.map { |v| v.split(/ *[,;] */) }.flatten
    # Do some type-specific validation of each of these values.
    values = values.map { |v| self.send("clean_#{type}", v) }
    # And exclude that are empty after that cleaning:
    values = values.reject { |v| v.empty? }
    # If there are multiple values, they should be semi-colon-joined:
    values.join(';')
  end

  def clean_email(value)
    value[VALID_EMAIL_REGEX, 0] || ''
  end

  def clean_phone(value)
    # If there are more than 15 digits, this is probably multiple
    # phone numbers:
    digit_count = value.scan(/\d/).count
    if digit_count == 0
      ''
    elsif digit_count > 15
      raise RuntimeError, "Probably more than one phone no. in '#{value}'"
    elsif digit_count < 5
      raise RuntimeError, "Not enough digits for a phone no. in '#{value}'"
    else
      value.gsub(/[^-+ \d]/, '')
    end
  end

  def clean_twitter(value)
    value[TWITTER_USERNAME_REGEX, 1] || ''
  end

  def clean_facebook(value)
    clean_url(value)
  end

  def clean_website(value)
    clean_url(value)
  end

  def clean_url(value)
    return '' if (value.empty? || value == '...')
    if value[/\Ahttps?:\/\//]
      value
    else
      "http://#{value}"
    end
    value[VALID_URL_REGEX] || ''
  end
end

class GovernorsList < Scraped::HTML
  field :governors do
    noko.css('div#content table tr').drop(1).map do |governor|
      Governor.new(response: response, noko: governor)
    end
  end
end

list = 'http://www.nigeriaembassyusa.org/index.php?page=state-governors'
page = GovernorsList.new(response: Scraped::Request.new(url: list).response)

ScraperWiki.sqliteexecute('DELETE FROM data') rescue nil
page.governors.each do |governor|
  ScraperWiki.save_sqlite([:name], governor.to_h)
end
