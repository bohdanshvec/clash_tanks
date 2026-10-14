module GameEngine
  class Action
    attr_reader :player_id, :type, :payload

    def initialize(player_id:, type:, payload: {})
      @player_id = player_id
      @type = type
      @payload = deep_dup_and_freeze(payload)
      freeze
    end

    private

    def deep_dup_and_freeze(value)
      copy = case value
             when Hash
               value.each_with_object({}) do |(key, item), result|
                 result[deep_dup_and_freeze(key)] =
                   deep_dup_and_freeze(item)
               end
             when Array
               value.map { |item| deep_dup_and_freeze(item) }
             else
               value
             end

      copy.freeze
    end
  end
end
