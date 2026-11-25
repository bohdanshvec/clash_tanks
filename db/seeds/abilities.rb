[
  { code: "damage_technique", name: "Пошкодження техніки" },
  { code: "draw_cards", name: "Добір карт" },
  { code: "headquarters_defender", name: "Захисник штабу" }
].each do |attributes|
  ability = Ability.find_or_initialize_by(code: attributes[:code])
  ability.assign_attributes(attributes)
  ability.save!
end
