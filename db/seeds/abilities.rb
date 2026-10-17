[
  { code: "damage_technique", name: "Пошкодження техніки" },
  { code: "draw_cards", name: "Добір карт" }
].each do |attributes|
  ability = Ability.find_or_initialize_by(code: attributes[:code])
  ability.assign_attributes(attributes)
  ability.save!
end
