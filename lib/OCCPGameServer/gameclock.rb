module OCCPGameServer

    class GameClock
        
        @clockStates = {:paused => 'PAUSED', :running => 'RUNNING' }

#        attr_accessor :gamelength
#        attr_reader :elapsedtime, :starttime, :endtime
        
        def initialize
            @mutex = Mutex.new
            @clockstate = :paused
            @lastreadtime = Time.now
            @gametime = 0

        end
        def set_gamelength(time, format)
           # @gamelength = DateTime.strptime(time, format)
           case format
           when "seconds"
               @gamelength = time.to_i
           when "minutes"
               @gamelength = time.to_i * 60
           when "hours"
               @gamelength = time.to_i * 60 * 60
           end
        end
        def gamelength
            @gamelength
        end

        def start
            @mutex.synchronize do
                @lastreadtime = Time.now
                @clockstate = :running
            end
        end
        
        def resume
            @mutex.synchronize do
                @lastreadtime = Time.now
                @clockstate = :running
            end
        end

        def pause
            @mutex.synchronize do
                @gametime = Time.now - @lastreadtime + @gametime
                @clockstate = :paused
            end
        end

        def gametime

            if @clockstate === :paused
                @gametime
            else
                @mutex.synchronize do
                    moment = Time.now
                    @gametime = moment - @lastreadtime + @gametime
                    @lastreadtime = moment
                end
                @gametime
            end
        end


    end

end
