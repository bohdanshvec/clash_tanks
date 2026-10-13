# app/services/game_engine/state_digest.rb

require "digest"
require "json"

module GameEngine
  class StateDigest
    def self.call(state)
      canonical_state = canonicalize(state)

      Digest::SHA256.hexdigest(
        JSON.generate(canonical_state)
      )
    end

    def self.canonicalize(value)
      case value
      when Hash
        value.keys.sort_by(&:to_s).each_with_object({}) do |key, result|
          result[key.to_s] = canonicalize(value.fetch(key))
        end
      when Array
        value.map { |item| canonicalize(item) }
      else
        value
      end
    end

    private_class_method :canonicalize
  end
end
