module Riiif
  class ImagesController < ::ApplicationController
    before_filter :link_header, only: [:show, :info]

    rescue_from Riiif::InvalidAttributeError do
      render nothing: true, status: 400
    end

    def show
      begin
        image = model.new(image_id)
        status = if authorization_service.can?(:show, image)
                   :ok
                 else
                   :unauthorized
                 end
      rescue ImageNotFoundError
        status = :not_found
      end

      image = not_found_image unless status == :ok

      data = image.render(params.permit(:region, :size, :rotation, :quality, :format))
      headers['Access-Control-Allow-Origin'] = '*'
      send_data data,
                status: status,
                type: Mime::Type.lookup_by_extension(params[:format]),
                disposition: 'inline'
    end

    def info
      image = model.new(image_id)
      info = image.info.merge(server_info).merge(authorization_service.service_info(image))
      if authorization_service.can?(:info, image)
        headers['Access-Control-Allow-Origin'] = '*'
        render json: info, content_type: 'application/ld+json'
      elsif authorization_service.has_degraded?(image)
        redirect_to authorization_service.degraded_image_uri(image)
      else
        render json: info, status: :unauthorized
      end
    end

    # this is a workaround for https://github.com/rails/rails/issues/25087
    def redirect
      # This was attempted with just info_path, but it gave a NoMethodError
      redirect_to Riiif::Engine.routes.url_helpers.info_path(params[:id])
    end

    protected

      LEVEL1 = 'http://iiif.io/api/image/2/level1.json'.freeze

      def model
        params.fetch(:model, 'riiif/image').camelize.constantize
      end

      def image_id
        params[:id]
      end

      def authorization_service
        model.authorization_service.new(self)
      end

      def link_header
        response.headers['Link'] = "<#{LEVEL1}>;rel=\"profile\""
      end

      def not_found_image
        raise "Not found image doesn't exist" unless Riiif.not_found_image
        model.new(image_id, Riiif::File.new(Riiif.not_found_image))
      end

      CONTEXT = '@context'.freeze
      CONTEXT_URI = 'http://iiif.io/api/image/2/context.json'.freeze
      ID = '@id'.freeze
      PROTOCOL = 'protocol'.freeze
      PROTOCOL_URI = 'http://iiif.io/api/image'.freeze
      PROFILE = 'profile'.freeze

      def server_info
        {
          CONTEXT => CONTEXT_URI,
          ID => request.original_url.sub('/info.json', ''),
          PROTOCOL => PROTOCOL_URI,
          PROFILE => [LEVEL1, 'formats' => model::OUTPUT_FORMATS]
        }
      end
  end
end
