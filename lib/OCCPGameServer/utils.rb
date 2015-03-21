module OCCPGameServer
    require_relative './constants'

    #
    # Validate that the value given is an actual system STATE as defined in constants.rb
    #
    def self.valid_state(state)
        case state
        when WAIT, READY , RUN , STOP , QUIT
            return true
        end
        return false
    end

end
