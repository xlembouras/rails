require 'active_support/core_ext/hash/conversions'
require 'action_dispatch/http/request'
require 'active_support/core_ext/hash/indifferent_access'

module ActionDispatch
  class ParamsParser
    class ParseError < StandardError
      attr_reader :original_exception

      def initialize(message, original_exception)
        super(message)
        @original_exception = original_exception
      end
    end

    DEFAULT_PARSERS = {
      Mime::JSON => lambda { |raw_post|
        data = ActiveSupport::JSON.decode(raw_post)
        data = {:_json => data} unless data.is_a?(Hash)
        Request::Utils.deep_munge(data).with_indifferent_access
      }
    }

    def initialize(app, parsers = {})
      @app, @parsers = app, DEFAULT_PARSERS.merge(parsers)
    end

    def call(env)
      if params = parse_formatted_parameters(env)
        env["action_dispatch.request.request_parameters"] = params
      end

      @app.call(env)
    end

    private
      def parse_formatted_parameters(env)
        request = Request.new(env)

        return false if request.content_length.zero?

        strategy = @parsers.fetch(request.content_mime_type) { return false }

        strategy.call(request.raw_post)

      rescue => e # JSON or Ruby code block errors
        logger(env).debug "Error occurred while parsing request parameters.\nContents:\n\n#{request.raw_post}"

        raise ParseError.new(e.message, e)
      end

      def logger(env)
        env['action_dispatch.logger'] || ActiveSupport::Logger.new($stderr)
      end
  end
end
