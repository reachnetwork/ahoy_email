module Ahoy
  class MessagesController < ActionController::Base
    if respond_to? :before_action
      before_action :check_referrer
      before_action :set_message
    else
      before_filter :check_referrer
      before_filter :set_message
    end

    def open
      if @message && !@message.opened_at
        @message.opened_at = Time.now
        @message.save!

        publish :open
      end

      send_data Base64.decode64("R0lGODlhAQABAPAAAAAAAAAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw=="), type: "image/gif", disposition: "inline"
    end

    def click
      url = params[:url].to_s

      # rescue any error and redirect to original URL to avoid seeing 500 errors
      begin
        if @message && !@message.clicked_at
          @message.clicked_at = Time.now
          @message.opened_at ||= @message.clicked_at
          @message.save!
        end
        
        publish :click, url: params[:url]

        signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha1"), AhoyEmail.secret_token, url)

        if secure_compare(params[:signature].to_s, signature)
          redirect_to url
        else
          redirect_to AhoyEmail.invalid_redirect_url || main_app.root_url
        end
      rescue StandardError => e
        Honeybadger.notify(e)

        redirect_to url
      end
    end

    protected

    def set_message
      @message = AhoyEmail.message_model.where(token: params[:id]).first
    end

    def publish(name, event = {})
      AhoyEmail.subscribers.each do |subscriber|
        if subscriber.respond_to?(name)
          event[:message] = @message
          event[:controller] = self
          subscriber.send name, event
        end
      end
    end

    # from https://github.com/rails/rails/blob/master/activesupport/lib/active_support/message_verifier.rb
    # constant-time comparison algorithm to prevent timing attacks
    def secure_compare(a, b)
      return false unless a.bytesize == b.bytesize

      l = a.unpack "C#{a.bytesize}"

      res = 0
      b.each_byte { |byte| res |= byte ^ l.shift }
      res == 0
    end

    # Only allow external opens and clicks
    def check_referrer
      if request.referrer.present?
        uri_ref = URI.parse(request.referrer)
        return if AhoyEmail.blacklisted_referrers.include?(uri_ref.host)
      end
    end
  end
end
