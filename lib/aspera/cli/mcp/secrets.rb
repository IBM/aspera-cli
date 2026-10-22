# frozen_string_literal: true

require 'aspera/secret_hider'
require 'aspera/cli/error'
require 'aspera/cli/info'
require 'aspera/cli/web_secret'
require 'json'

module Aspera
  module Cli
    module Mcp
      # Secrets of extended value `@secret:` in MCP server mode, entered by the user on a web page (see WebSecret).
      # The MCP client opens the page following a URL mode elicitation, so that the secret never passes through
      # the MCP client or the AI model.
      # See: https://modelcontextprotocol.io/specification/2026-07-28/client/elicitation
      module Secrets
        # Tag thrown, with the prompt, when a tool call needs a secret not requested yet
        THROW_TAG = :mcp_secret_required
        # Fiber-local variable holding the secrets of the tool call in progress
        CALL_KEY = :aspera_mcp_secret_call
        private_constant :CALL_KEY

        class << self
          # @param base_url    [String, nil] URL of the MCP server, `nil` to start a local web server on first request
          # @param access_code [String, nil] If set, the user must also enter it on the page (`auth_token` of the server)
          # @return [WebSecret] Secret pages of the MCP server
          def web_secret(base_url: nil, access_code: nil)
            WebSecret.new(base_url: base_url, access_code: access_code, name: "#{Info::CMD_NAME} MCP server", requester: 'AI assistant')
          end

          # Value of extended value `@secret:` for the tool call in progress
          # @param prompt [String] Name of the secret
          # @return [String] The secret
          def value(prompt)
            call = Thread.current[CALL_KEY]
            raise BadArgument, '@secret: is available only in MCP tool calls' if call.nil?
            call.value(prompt.empty? ? 'secret' : prompt)
          end

          # Execute the block with the secrets of the given tool call available to `@secret:`
          # @param call [Call] Secrets of the tool call
          def with_call(call)
            previous = Thread.current[CALL_KEY]
            Thread.current[CALL_KEY] = call
            yield
          ensure
            Thread.current[CALL_KEY] = previous
          end
        end

        # Secrets of one tool call.
        # Following MCP multi round-trip requests, the tool call is executed again from the start on each round:
        # `@secret:` values are taken in order from the requests of previous rounds, listed in the request state.
        class Call
          # @param web_secret     [WebSecret, nil]          Secret pages, `nil` if `@secret:` is not available
          # @param server_context [MCP::ServerContext, nil] Context of the tool call
          def initialize(web_secret, server_context)
            @web_secret     = web_secret
            @server_context = server_context
            @ids            = request_ids(server_context&.request_state)
            @next           = 0
          end

          # @param prompt [String] Name of the secret
          # @return [String] The secret entered by the user, waiting for it if needed
          # @throw THROW_TAG with the prompt if the secret was not requested yet
          def value(prompt)
            raise BadArgument, '@secret: is not available' if @web_secret.nil?
            throw(THROW_TAG, prompt) if @next >= @ids.size
            id = @ids[@next]
            @next += 1
            # The command is the same on each round, so prompts come in the same order
            raise BadArgument, 'Secret request expired or command changed: execute the command again' unless @web_secret.prompt(id).eql?(prompt)
            action = input_action(id)
            raise Error, "Secret request refused in MCP client: #{action}" unless action.nil? || action.eql?('accept')
            value = @web_secret.wait_value(id) do |elapsed|
              @server_context&.report_progress(elapsed.to_i, message: "Waiting for secret #{prompt} entered in browser")
            end
            # Clients of protocol 2025-11-25: completion of the out-of-band interaction
            @server_context.notify_elicitation_complete(elicitation_id: id) unless action.nil? || @server_context.modern?
            # Never reaches the client, even if displayed by the command
            SecretHider.instance.add_secret_values(value)
            value
          end

          # @return [Boolean] `true` if the MCP client supports URL mode elicitation
          def url_elicitation?
            !@web_secret.nil? && !read_key(read_key(@server_context&.client_capabilities, :elicitation), :url).nil?
          end

          # Request a new secret: the client asks the user to open the page, then executes the tool call again
          # @param prompt [String] Name of the secret
          # @return [MCP::Server::InputRequiredResult]
          def input_required(prompt)
            id = @web_secret.create(prompt)
            @ids.push(id)
            params = {
              mode:    'url',
              url:     @web_secret.url(id),
              message: "#{Info::CMD_NAME} needs secret \"#{prompt}\" to execute the command. " \
                'Enter it on the web page: it is sent to the MCP server only, not to the AI assistant.'
            }
            # Clients of protocol 2025-11-25: identifier of the out-of-band interaction
            params[:elicitationId] = id unless @server_context.modern?
            MCP::Server::InputRequiredResult.new(
              input_requests: {id => {method: 'elicitation/create', params: params}},
              request_state:  JSON.generate(@ids)
            )
          end

          # Forget the secrets of this call
          def finish
            @web_secret&.delete(@ids)
          end

          private

          # @param state [String, nil] Request state echoed by the client (unsealed by the MCP server)
          # @return [Array<String>] Identifiers of the requests of previous rounds
          def request_ids(state)
            return [] if state.nil?
            ids = JSON.parse(state) rescue nil
            raise BadArgument, 'Invalid request state' unless ids.is_a?(Array) && ids.all?(String)
            ids
          end

          # @param id [String] Identifier of the request
          # @return [String, nil] Action of the user in the MCP client (`accept`, `decline`, `cancel`), `nil` if not in this round
          def input_action(id)
            response = @server_context&.input_response(id)
            read_key(response, :action)&.to_s
          end

          # Read a key of a JSON object, parsed with or without symbolized keys
          def read_key(hash, key)
            return unless hash.is_a?(Hash)
            hash.key?(key) ? hash[key] : hash[key.to_s]
          end
        end
      end
    end
  end
end
