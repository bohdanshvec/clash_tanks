module AiPlayers
  class Setup
    AI_EMAIL = "ai@clash-tanks.local"
    AI_NAME = "AI"

    def self.call
      new.call
    end

    def call
      existing_ai = Player.find_by(ai: true)
      return existing_ai if existing_ai

      create_ai_player
    rescue ActiveRecord::RecordNotUnique
      # Если два запроса одновременно создавали ИИ,
      # используем запись, которую успел создать другой запрос.
      existing_ai = Player.find_by(ai: true)
      return existing_ai if existing_ai

      raise
    end

    private

    def create_ai_player
      Player.transaction do
        existing_player = Player.find_by(email: AI_EMAIL)

        if existing_player
          unless existing_player.ai?
            raise(
              "Email #{AI_EMAIL} is already used by a non-AI player"
            )
          end

          existing_player
        else
          Player.create!(
            email: AI_EMAIL,
            name: AI_NAME,
            password: SecureRandom.hex(32),
            guest: false,
            ai: true
          )
        end
      end
    end
  end
end
