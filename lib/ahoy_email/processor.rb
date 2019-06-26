module AhoyEmail
  class Processor
    attr_reader :message, :mailer, :ahoy_message

    UTM_PARAMETERS = %w(utm_source utm_medium utm_term utm_content utm_campaign)

    def initialize(message, mailer = nil)
      @message = message
      @mailer = mailer
    end

    def process
      Safely.safely do
        action_name = mailer.action_name.to_sym
        if options[:message] && (!options[:only] || options[:only].include?(action_name)) && !options[:except].to_a.include?(action_name)
          @ahoy_message = AhoyEmail.message_model.new
          ahoy_message.token = generate_token
          ahoy_message.to = Array(message.to).join(", ") if ahoy_message.respond_to?(:to=)
          ahoy_message.user = options[:user]

          track_open if options[:open]
          track_links if options[:utm_params] || options[:click]

          ahoy_message.mailer = options[:mailer] if ahoy_message.respond_to?(:mailer=)
          ahoy_message.subject = message.subject if ahoy_message.respond_to?(:subject=)
          ahoy_message.content = message.to_s if ahoy_message.respond_to?(:content=)

          UTM_PARAMETERS.each do |k|
            ahoy_message.send("#{k}=", options[k.to_sym]) if ahoy_message.respond_to?("#{k}=")
          end

          ahoy_message.assign_attributes(options[:extra] || {})

          ahoy_message.save!
          message["Ahoy-Message-Id"] = ahoy_message.id.to_s
        end
      end
    end

    def track_send
      Safely.safely do
        if (message_id = message["Ahoy-Message-Id"]) && message.perform_deliveries
          ahoy_message = AhoyEmail.message_model.where(id: message_id.to_s).first
          if ahoy_message
            ahoy_message.sent_at = Time.now
            ahoy_message.save
          end
          message["Ahoy-Message-Id"] = nil
        end
      end
    end

    protected

    def options
      @options ||= begin
        options = AhoyEmail.options.merge(mailer.class.try(:ahoy_options) || {})
        if mailer.try(:ahoy_options)
          options = options.except(:only, :except).merge(mailer.ahoy_options)
        end
        options.each do |k, v|
          if v.respond_to?(:call)
            options[k] = v.call(message, mailer)
          end
        end
        options
      end
    end

    def generate_token
      SecureRandom.urlsafe_base64(32).gsub(/[\-_]/, "").first(32)
    end

    def track_open
      if html_part?
        raw_source = (message.html_part || message).body.raw_source
        regex = /<\/body>/i
        url =
          url_for(
            controller: "ahoy/messages",
            action: "open",
            id: ahoy_message.token,
            format: "gif"
          )
        pixel = ActionController::Base.helpers.image_tag(url, size: "1x1", alt: "")

        # try to add before body tag
        if raw_source.match(regex)
          raw_source.gsub!(regex, "#{pixel}\\0")
        else
          raw_source << pixel
        end
      end
    end

    def track_links
      if html_part?
        body = (message.html_part || message).body
        doc = Nokogiri::HTML(body.raw_source)
        doc.css("a[href]").each do |link|
          uri = parse_uri(link["href"])
          params = []

          next unless trackable?(uri)
          # utm params first
          if options[:utm_params] && !skip_attribute?(link, "utm-params")
            params = uri.query_values(Array) || []
            UTM_PARAMETERS.each do |key|
              next if params.any? { |k, _v| k == key } || !options[key.to_sym]
              params << [key, options[key.to_sym]]
            end

          end

          if options[:click] && !skip_attribute?(link, "click")
            params << [:atid, ahoy_message.token]
            params << [:utm_action, "click"]
          end

          uri.query_values = params if params.present?
          link["href"] = uri.to_s
        end

        # hacky
        body.raw_source.sub!(body.raw_source, doc.to_s)
      end
    end

    def html_part?
      (message.html_part || message).content_type =~ /html/
    end

    def skip_attribute?(link, suffix)
      attribute = "data-skip-#{suffix}"
      if link[attribute]
        # remove it
        link.remove_attribute(attribute)
        true
      elsif link["href"].to_s =~ /unsubscribe/i && !options[:unsubscribe_links]
        # try to avoid unsubscribe links
        true
      elsif link["href"].to_s.include?("/ahoy/messages/")
        # don't reparse links with ahoy tracking
        true
      else
        false
      end
    end

    # Filter trackable URIs, i.e. absolute one with http
    def trackable?(uri)
      uri && uri.absolute? && %w(http https).include?(uri.scheme)
    end

    # Parse href attribute
    # Return uri if valid, nil otherwise
    def parse_uri(href)
      # to_s prevent to return nil from this method
      Addressable::URI.parse(href.to_s) rescue nil
    end

    def url_for(opt)
      opt = (ActionMailer::Base.default_url_options || {})
            .merge(options[:url_options])
            .merge(opt)
      AhoyEmail::Engine.routes.url_helpers.url_for(opt)
    end
  end
end
