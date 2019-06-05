module Ahoy::CallbacksControllable
  extend ActiveSupport::Concern

  included do
    prepend_before_action :tracking_callback
  end

  # This should be one of the first things that fires off within an application that support tracking URLs.
  # This will parse the parameters and then send a get request to the appropriate url
  def tracking_callback
    return if AhoyEmail.tracking_callback_url.blank?
    return if callback_params[:id].blank? || callback_params[:signature].blank?

    begin
      uri = URI("#{AhoyEmail.tracking_callback_url}/#{callback_params[:id]}/#{callback_params[:utm_action]}")
      dupe_callback_params = callback_params.to_h
      dupe_callback_params[:redirect] = false
      dupe_callback_params[:url] = "#{request.scheme}://www.#{request.host}#{request.path}"
      uri.query = URI.encode_www_form(dupe_callback_params)
      Net::HTTP.get_response(uri)
    rescue StandardError => e
      Honeybadger.notify(e)
    end
  end

  private

  def callback_params
    params.permit(
      :id,
      :signature,
      :utm_source,
      :utm_medium,
      :utm_campaign,
      :utm_action,
      :path
    )
  end
end
