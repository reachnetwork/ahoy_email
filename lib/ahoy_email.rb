require "active_support"
require "nokogiri"
require "addressable/uri"
require "openssl"
require "safely/core"
require "ahoy_email/processor"
require "ahoy_email/interceptor"
require "ahoy_email/mailer"
require "ahoy_email/engine"
require "ahoy_email/version"

module AhoyEmail
  mattr_accessor :secret_token, :options, :subscribers, :belongs_to, :invalid_redirect_url, :tracking_callback_url

  self.options = {
    message: true,
    open: true,
    click: true,
    utm_params: true,
    utm_source: proc { |message, mailer| mailer.mailer_name },
    utm_medium: "email",
    utm_term: nil,
    utm_content: nil,
    utm_campaign: proc { |message, mailer| mailer.action_name },
    user: proc { |message, mailer| (message.to.size == 1 ? User.where(email: message.to.first).first : nil) rescue nil },
    mailer: proc { |message, mailer| "#{mailer.class.name}##{mailer.action_name}" },
    url_options: {}
  }

  self.subscribers = []

  self.belongs_to = {}

  self.tracking_callback_url = case Rails.env
  when 'production'
    'https://outreach.reachnetwork.com/ahoy/messages'
  when 'staging'
    'https://outreach.staging.reachnetwork.com/ahoy/messages'
  else
    'http://outreach.reachnetwork.test/ahoy/messages'
  end

  def self.track(options)
    self.options = self.options.merge(options)
  end

  class << self
    attr_writer :message_model, :processor, :blacklisted_referrers
  end

  def self.message_model
    (defined?(@message_model) && @message_model) || ::Ahoy::Message
  end

  def self.processor
    (defined?(@processor) && @processor) || ::AhoyEmail::Processor
  end

  def self.blacklisted_referrers
    (defined?(@blacklisted_referrers) && @blacklisted_referrers) || []
  end
end

ActiveSupport.on_load(:action_mailer) do
  include AhoyEmail::Mailer
  register_interceptor AhoyEmail::Interceptor
end
