# frozen_string_literal: true

module BrowseTagsHelper
  def format_key(key)
    if url = wiki_link("key", key)
      link_to h(key), url, :title => t("browse.tag_details.wiki_link.key", :key => key)
    else
      h(key)
    end
  end

  def format_value(key, value)
    if /\Afixme/i.match?(key)
      # Values of fixme tags don't need to be parsed and linkified.
      h(value)
    elsif wp = wikipedia_links(key, value)
      # IMPORTANT: Note that wikipedia_links() and wikidata_links() each return an array of hashes,
      # unlike for example wikimedia_commons_link(), which just returns one such hash.
      wp = wp.map do |w|
        link_to(h(w[:title]), w[:url], :title => t("browse.tag_details.wikipedia_link", :page => w[:title]))
      end
      safe_join(wp, ";")
    elsif wdt = wikidata_links(key, value)
      svg = button_tag :type => "button", :role => "button", :class => "btn btn-link float-end d-flex m-1 mt-0 me-n1 border-0 p-0 wdt-preview", :data => { :qids => wdt.pluck(:title) } do
        tag.svg :width => 27, :height => 16 do
          concat tag.title t("browse.tag_details.wikidata_preview", :count => wdt.length)
          concat tag.path :fill => "currentColor", :d => "M0 16h1V0h-1Zm2 0h3V0h-3Zm4 0h3V0h-3Zm4 0h1V0h-1Zm2 0h1V0h-1Zm2 0h3V0h-3Zm4 0h1V0h-1Zm2 0h3V0h-3Zm4 0h1V0h-1Zm2 0h1V0h-1Z"
        end
      end
      wdt = wdt.map do |w|
        link_to(w[:title], w[:url], :title => t("browse.tag_details.wikidata_link", :page => w[:title].strip))
      end
      svg + safe_join(wdt, ";")
    elsif wmc = wikimedia_commons_link(key, value)
      link_to h(wmc[:title]), wmc[:url], :title => t("browse.tag_details.wikimedia_commons_link", :page => wmc[:title])
    elsif url = wiki_link("tag", "#{key}=#{value}")
      link_to h(value), url, :title => t("browse.tag_details.wiki_link.tag", :key => key, :value => value)
    elsif email = email_link(key, value)
      mail_to(email, :title => t("browse.tag_details.email_link", :email => email))
    elsif phones = telephone_links(key, value)
      # similarly, telephone_links() returns an array of phone numbers
      phones = phones.map do |p|
        link_to(h(p[:phone_number]), p[:url], :title => t("browse.tag_details.telephone_link", :phone_number => p[:phone_number]))
      end
      safe_join(phones, "; ")
    elsif colour_value = colour_preview(key, value)
      svg = tag.svg :width => 14, :height => 14, :class => "float-end m-1" do
        concat tag.title t("browse.tag_details.colour_preview", :colour_value => colour_value)
        concat tag.rect :x => 0.5, :y => 0.5, :width => 13, :height => 13, :fill => colour_value, :stroke => "#2222"
      end
      svg + colour_value
    else
      safe_join(value.split(";", -1).map { |x| tag2link_link(key, x) || linkify(h(x)) }, ";")
    end
  end

  private

  def wiki_link(type, lookup)
    locale = I18n.locale.to_s

    # update-wiki-pages does s/ /_/g on keys before saving them, we
    # have to replace spaces with underscore so we'll link
    # e.g. `source=Isle of Man Government aerial imagery (2001)' to
    # the correct page.
    lookup_us = lookup.tr(" ", "_")

    page = WIKI_PAGES.dig(locale, type, lookup_us) ||
           WIKI_PAGES.dig("en", type, lookup_us)

    url = "https://wiki.openstreetmap.org/wiki/#{page}?uselang=#{locale}" if page

    url
  end

  def wikipedia_links(key, value)
    # This regex should match all Wikipedia language codes, everything
    # from ab (Abkhaz) to zh-classical (Classical Chinese)
    key_re = /\A([a-z_:]+:)?wikipedia(:(?<lang>[a-zA-Z-]{2,12}))?\z/o

    # Accept `wikipedia` and secondary Wikipedia links as keys
    return nil unless key_re.match?(key)
    # Some k/v's are wikipedia=http://en.wikipedia.org/wiki/Full%20URL
    return nil if %r{^https?://}i.match?(value)

    lang = key_re.match(key).named_captures()["lang"] || "en"

    # Match all semicolon-separated Wikipedia links
    value.split(";").map do |wikipedia_value|
      wikipedia_value = wikipedia_value.strip

      value_re = /\A((?<lang>[a-z-]{2,12}):)?(?<title>[^#]+)(#(?<section>.+)?)?\z/oi
      matches = value_re.match(wikipedia_value)

      page_lang = matches.named_captures()["lang"] || lang
      title = matches.named_captures()["title"]
      section = matches.named_captures()["section"]

      url = "https://#{page_lang}.wikipedia.org/wiki/#{wiki_encode(title)}?uselang=#{I18n.locale}"
      url += "##{wiki_encode(section)}" if section
      {:url => url, :title => title}
    end
  end

  def wiki_encode(s)
    u s.tr(" ", "_")
  end

  def wikidata_links(key, value)
    # Accept simple and secondary Wikidata links as keys
    return nil unless /\A([a-z_:]+:)?wikidata\z/.match?(key)

    # Value has to be a semicolon-separated list of wikidata-IDs (whitespaces allowed before and after semicolons)
    # The simple wikidata-tag is limited to only one value, however we don't need to care.
    value.split(";").map do |wd_id|
      # normalize
      wd_id = wd_id.strip.upcase

      # Give up if any of the semicolon-separated values does not meet expectation.
      return nil unless /\AQ[1-9][0-9]*\z/o.match?(wd_id)

      puts wd_id
      {:url => "https://wikidata.org/entity/#{wd_id}?uselang=#{I18n.locale}"}
    end
  end

  def wikimedia_commons_link(key, value)
    # Allow any simple and secondary Wikimedia Commons link.
    return nil unless /\A([a-z_:]+:)?wikimedia_commons\z/.match?(key)

    # matches everything up to potential # and throw away the rest.
    # In case there is a link to an anchor in the Wikimedia Commons page. We will ignore that, as it is not really standard to link to anchors.
    # OSM Wiki (https://wiki.openstreetmap.org/wiki/Key:wikimedia_commons) states value syntax as `File:xxxxxx.xxx / Category:xxxxx`.
    # Hence we only accept these two namespaces.
    value_re = /\A(?<namespace>File|Category):(?<title>[^#]+)/i
    return nil unless value_re.match?(value)

    match = value_re.match(value)
    namespace = match.named_captures()["namespace"].capitalize
    title = match.named_captures()["title"]

    return {
      :url => "https://commons.wikimedia.org/wiki/#{namespace}:#{u title}?uselang=#{I18n.locale}",
      :title => title
    }
  end

  def tag2link_link(key, value)
    link = Tag2link.link(key, value)
    return nil unless link

    link_to(h(value), link, :rel => "nofollow")
  end

  def email_link(key, value)
    # Avoid converting conditional tags into emails, since EMAIL_REGEXP is quite permissive
    return nil unless %w[email contact:email].include? key

    # Does the value look like an email? eg "someone@domain.tld"

    #  Uses Ruby built-in regexp to validate email.
    #  This will not catch certain valid emails containing comments, whitespace characters,
    #  and quoted strings.
    #    (see: https://github.com/ruby/ruby/blob/master/lib/uri/mailto.rb)

    # remove any leading and trailing whitespace
    email = value.strip

    return email if email.match?(URI::MailTo::EMAIL_REGEXP)

    nil
  end

  def telephone_links(_key, value)
    # Does it look like a global phone number? eg "+1 (234) 567-8901 "
    # or a list of alternate numbers separated by ;
    #
    # Per RFC 3966, this accepts the visual separators -.() within the number,
    # which are displayed and included in the tel: URL, and accepts whitespace,
    # which is displayed but not included in the tel: URL.
    #  (see: http://tools.ietf.org/html/rfc3966#section-5.1.1)
    #
    # Also accepting / as a visual separator although not given in RFC 3966,
    # because it is used as a visual separator in OSM data in some countries.
    if value.match?(%r{^\s*\+[\d\s()/.-]{6,25}\s*(;\s*\+[\d\s()/.-]{6,25}\s*)*$})
      return value.split(";").map do |phone_number|
        # for display, remove leading and trailing whitespace
        phone_number = phone_number.strip

        # for tel: URL, remove all whitespace
        # "+1 (234) 567-8901 " -> "tel:+1(234)567-8901"
        phone_no_whitespace = phone_number.gsub(/\s+/, "")
        { :phone_number => phone_number, :url => "tel:#{phone_no_whitespace}" }
      end
    end
    nil
  end

  def colour_preview(key, value)
    return nil unless key =~ /^(?>.+:)?colour$/ && !value.nil? # see discussion at https://github.com/openstreetmap/openstreetmap-website/pull/1779

    # does value look like a colour? ( 3 or 6 digit hex code or w3c colour name)
    w3c_colors =
      %w[aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet brown burlywood cadetblue chartreuse chocolate
         coral cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray darkgrey darkgreen darkkhaki darkmagenta darkolivegreen
         darkorange darkorchid darkred darksalmon darkseagreen darkslateblue darkslategray darkslategrey darkturquoise darkviolet deeppink deepskyblue
         dimgray dimgrey dodgerblue firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray grey green greenyellow honeydew
         hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan lightgoldenrodyellow lightgray
         lightgrey lightgreen lightpink lightsalmon lightseagreen lightskyblue lightslategray lightslategrey lightsteelblue lightyellow lime limegreen
         linen magenta maroon mediumaquamarine mediumblue mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen mediumturquoise
         mediumvioletred midnightblue mintcream mistyrose moccasin navajowhite navy oldlace olive olivedrab orange orangered orchid palegoldenrod
         palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum powderblue purple red rosybrown royalblue saddlebrown salmon
         sandybrown seagreen seashell sienna silver skyblue slateblue slategray slategrey snow springgreen steelblue tan teal thistle tomato turquoise
         violet wheat white whitesmoke yellow yellowgreen]
    return nil unless value =~ /^#([0-9a-fA-F]{3}){1,2}$/ || w3c_colors.include?(value.downcase)

    value
  end
end
