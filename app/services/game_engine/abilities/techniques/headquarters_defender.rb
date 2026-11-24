
module GameEngine
  module Abilities
    module Techniques
      class HeadquartersDefender
        CODE = "headquarters_defender"

        DESCRIPTION = "Приймає урон штабу, знаходячись на плацдармі."

        def self.description(_parameters = {})
          DESCRIPTION
        end
      end
    end
  end
end
