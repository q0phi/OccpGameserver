module OCCPGameServer

    class GameClock
#        attr_accessor :gamelength
        attr_reader :elapsedtime, :starttime, :endtime

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
        end

        def pause
        end

        def get_clock
        end

    end

end
