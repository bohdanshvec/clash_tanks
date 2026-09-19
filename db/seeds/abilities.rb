[
  { code: "damage_technique", name: "Damage Technique" },
  { code: "draw_cards", name: "Draw Cards" }
].each do |attributes|
  ability = Ability.find_or_initialize_by(code: attributes[:code])
  ability.assign_attributes(attributes)
  ability.save!
end
