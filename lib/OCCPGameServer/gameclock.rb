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
            @watchdog = nil

        end
        def startwatchdog
            @watchdog = Thread.new { 
                sleep(@gamelength-gametime) 
                if gametime >= @gamelength
                    puts "Game Clock Expired!"
                    $log.info "====== Game Clock Expired! ======"
                    $appCore.INBOX << GMessage.new({:fromid=>'Watchdog',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> STOP}})              
                end
            }
        end
        def stopwatchdog
            if @watchdog.kind_of? Thread and @watchdog.alive?
                @watchdog.kill
            end
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
           stopwatchdog
           startwatchdog
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
            if @clockstate === :running
                return true
            end
            @mutex.synchronize do
                @lastreadtime = Time.now
                @clockstate = :running
            end
            startwatchdog
        end

        def pause
            if @clockstate === :paused
                return true
            end
            stopwatchdog
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
