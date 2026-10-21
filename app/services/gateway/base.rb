# app/services/gateway/base.rb

module Gateway
  class Base
    attr_reader :config

    def initialize(gateway_config)
      @config = gateway_config
    end

    # Subclasses must implement this
    def process(_order)
      raise NotImplementedError, "#{self.class.name} must implement #process"
    end

    private

    def http_client
      # Return a configured HTTP client (Faraday, Net::HTTP, etc.)
    end
  end
end