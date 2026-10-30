module ApplicationHelper
  CARD_IMAGE_NATIONS = %w[usa germany ussr].freeze
  CARD_IMAGE_TYPES = %w[headquarters technique order platoon].freeze
  CARD_IMAGE_DISPLAYS = %w[field card].freeze

  CARD_BORDER_VARIANTS = {
    "headquarters" => %w[ability],
    "technique" => %w[ability],
    "order" => [],
    "platoon" => %w[attack defense]
  }.freeze

  def card_image_path(nation:, display:, type:, code:)
    nation, display, type =
      validate_card_image_options!(nation, display, type)

    code = code.to_s

    unless code.match?(/\A[\p{L}\p{N}_]+\z/u)
      raise ArgumentError, "Invalid card code: #{code.inspect}"
    end

    code = code.delete_prefix("#{nation}_")
    code = code.delete_prefix("#{type}_")

    if code.empty?
      raise ArgumentError, "Card image code cannot be empty"
    end

    filename = "#{nation}_#{display}_#{type}_#{code}.png"

    "cards/#{nation}/#{type}/#{filename}"
  end

  def card_border_path(nation:, display:, type:, variant: nil)
    nation, display, type =
      validate_card_image_options!(nation, display, type)

    variant = variant.to_s.presence

    if variant && !CARD_BORDER_VARIANTS.fetch(type).include?(variant)
      raise ArgumentError, "Invalid border variant: #{variant.inspect}"
    end

    suffix = variant ? "_#{variant}" : ""

    filename = "#{nation}_#{display}_#{type}#{suffix}_border.png"

    "cards/#{nation}/#{type}/#{filename}"
  end

  private

  def validate_card_image_options!(nation, display, type)
    nation = nation.to_s
    display = display.to_s
    type = type.to_s

    unless CARD_IMAGE_NATIONS.include?(nation)
      raise ArgumentError, "Invalid card nation: #{nation.inspect}"
    end

    unless CARD_IMAGE_DISPLAYS.include?(display)
      raise ArgumentError, "Invalid card display: #{display.inspect}"
    end

    unless CARD_IMAGE_TYPES.include?(type)
      raise ArgumentError, "Invalid card type: #{type.inspect}"
    end

    if type == "order" && display == "field"
      raise ArgumentError, "Order cards do not have field images"
    end

    [nation, display, type]
  end
end