require 'omniauth'
require 'omniauth-saml'

module OmniAuth
  module SAML
    module MultiProvider
      class Handler
        attr_reader :path_prefix, :identity_provider_id_regex

        def initialize(path_prefix: OmniAuth.config.path_prefix,
                       identity_provider_id_regex: /\w+/, &identity_provider_options_generator)
          raise 'Missing provider options generator block' unless block_given?

          @path_prefix = path_prefix
          @identity_provider_id_regex = identity_provider_id_regex
          @identity_provider_options_generator = identity_provider_options_generator

          # Eagerly compute these since lazy evaluation will not be threadsafe
          @provider_path_prefix = "#{@path_prefix}/saml"
          @saml_path_regex = /^#{@provider_path_prefix}\/(?<identity_provider_id>#{@identity_provider_id_regex})/
          @request_path_regex = /#{saml_path_regex}\/?$/
          @callback_path_regex = /#{saml_path_regex}\/callback\/?$/
          @metadata_path_regex = /#{saml_path_regex}\/metadata\/?$/
        end

        def provider_options
          {
              request_path: method(:request_path?),
              callback_path: method(:callback_path?),
              metadata_path: method(:metadata_path?),
              setup: method(:setup)
          }
        end

        private

        attr_reader :provider_path_prefix, :saml_path_regex, :request_path_regex, :callback_path_regex,
                    :metadata_path_regex, :identity_provider_options_generator

        def setup(env)
          identity_provider_id = extract_identity_provider_id(env)
          if identity_provider_id
            strategy = env['omniauth.strategy']
            add_path_options(strategy, identity_provider_id)
            add_identity_provider_options(strategy, env, identity_provider_id)
          end
        end

        def add_path_options(strategy, identity_provider_id)
          strategy.options.merge!(
              request_path: "#{provider_path_prefix}/#{identity_provider_id}",
              callback_path: "#{provider_path_prefix}/#{identity_provider_id}/callback"
          )
        end

        def add_identity_provider_options(strategy, env, identity_provider_id)
          identity_provider_options = identity_provider_options_generator.call(identity_provider_id, env) || {}
          strategy.options.merge!(identity_provider_options)
        rescue => e
          result = strategy.fail!(:invalid_identity_provider, e)
          throw :warden, result
        end

        def request_path?(env)
          path = current_path(env)
          !!request_path_regex.match(path)
        end

        def callback_path?(env)
          path = current_path(env)
          !!callback_path_regex.match(path)
        end

        def metadata_path?(env)
          path = current_path(env)
          !!metadata_path_regex.match(path)
        end

        def current_path(env)
          env['PATH_INFO']
        end

        def extract_identity_provider_id(env)
          path = current_path(env)
          match = saml_path_regex.match(path)
          match ? match[:identity_provider_id] : nil
        end
      end
    end
  end
end
