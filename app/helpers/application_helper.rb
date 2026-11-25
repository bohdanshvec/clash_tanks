
module ApplicationHelper
  CARD_IMAGE_NATIONS = %w[usa germany ussr].freeze
  CARD_IMAGE_TYPES = %w[headquarters technique order platoon].freeze
  CARD_IMAGE_DISPLAYS = %w[field card].freeze

  CARD_BORDER_DISPLAYS = %w[field card deck hand].freeze

  CARD_BORDER_VARIANTS = {
    "headquarters" => %w[ability],
    "technique" => %w[ability],
    "order" => [],
    "platoon" => %w[attack defense]
  }.freeze

  ABILITY_DESCRIPTION_CLASSES = {
    GameEngine::Abilities::Orders::DamageTechnique::CODE =>
      GameEngine::Abilities::Orders::DamageTechnique,

    GameEngine::Abilities::Orders::DrawCards::CODE =>
      GameEngine::Abilities::Orders::DrawCards,

    GameEngine::Abilities::Techniques::HeadquartersDefender::CODE =>
      GameEngine::Abilities::Techniques::HeadquartersDefender
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

    filename = "#{nation}_#{display}_#{type}_#{code}.webp"

    "cards/#{nation}/#{type}/#{filename}"
  end

  def card_border_path(nation:, display:, type:, variant: nil)
    nation, display, type =
      validate_card_image_options!(
        nation,
        display,
        type,
        allowed_displays: CARD_BORDER_DISPLAYS
      )

    variant = variant.to_s.presence

    if variant && !CARD_BORDER_VARIANTS.fetch(type).include?(variant)
      raise ArgumentError, "Invalid border variant: #{variant.inspect}"
    end

    suffix = variant ? "_#{variant}" : ""

    filename =
      case display
      when "deck", "hand"
        "#{nation}_card_#{type}#{suffix}_border_#{display}.webp"
      else
        "#{nation}_#{display}_#{type}#{suffix}_border.webp"
      end

    "cards/#{nation}/#{type}/#{filename}"
  end

  def ability_description(code:, parameters: {})
    description_class = ABILITY_DESCRIPTION_CLASSES[code.to_s]

    description_class&.description(parameters)
  end

  private

  def validate_card_image_options!(
    nation,
    display,
    type,
    allowed_displays: CARD_IMAGE_DISPLAYS
  )
    nation = nation.to_s
    display = display.to_s
    type = type.to_s

    unless CARD_IMAGE_NATIONS.include?(nation)
      raise ArgumentError, "Invalid card nation: #{nation.inspect}"
    end

    unless allowed_displays.include?(display)
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
