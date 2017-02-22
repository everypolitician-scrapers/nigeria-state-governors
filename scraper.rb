#!/bin/env ruby
# encoding: utf-8

require 'date'
require 'nokogiri'
require 'open-uri'
require 'scraped'
require 'scraperwiki'

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
  puts "Saving #{governor}"
  ScraperWiki.save_sqlite([:name], governor.to_h)
end
