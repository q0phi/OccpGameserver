module OCCPGameServer

    attr_reader :uid
    attr_accessor :name

    class GChannel

        def initialize(sendQueue, name=nil)
  
            @uid = SecureRandom.uuid
            @OUTBOX = sendQueue
            @INBOX = Queue.new
            @messageCount = 0
            @name = name

        end

        def send(message)
            @OUTBOX << {:channelID => @uid, :number=>@messsageCount, :message => message}
        end


    end # end Class

end # end Module
