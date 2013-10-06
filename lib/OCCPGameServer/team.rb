module OCCPGameServer

    class Team #Really the TeamScheduler

        attr_accessor :teamname, :speedfactor, :teamhost

        #Thread State Modes
        WAIT = 1
        READY = 2
        RUN = 3
        STOP = 4

        
        def initialize()

            #Create an Instance variable to hold our events
            @events = Array.new
            
            @rawevents = Array.new

            @STATE = RUN

        end

        # Push a new event into our list
        def add_event(new_event)
            @events << new_event
        end
        
        # Push a new raw unprocessed event into our list
        def add_raw_event(new_event)
            @rawevents << new_event
        end

        def get_raw_events()
            @rawevents
        end

        def run(parent_main)

            puts @teamname + " Executing..."
           
            
            #Validate each event
            # @rawevents list is an array of event lists
            @rawevents.each {|eventlist|
                eventlist.find('team-event').each {|event|
                    
                    #First Identify the handler
                    handler_name = event.find("handler").first.attributes["name"]
                   
                    event_handler = parent_main.get_handler(handler_name)

                    this_event = event_handler.parse_event(event)

                    @events << this_event

                }
            
            }
            
            #Split the list into periodic and single events
            @singletonList = Array.new
            @periodicList = Array.new

            @events.each { |event|
                if event.freqscale === 'none'
                    @singletonList << event
                else
                    @periodicList << event
                end
            }
            
            #Sort into the order that they should be popped into the @eventRunQueue
            @singletonList.sort!{|aEv,bEv| aEv.starttime <=> bEv.starttime }

            #puts @singletonList.to_s.green

            #Signal ready and wait for start signal
            while true do
                
                if @STATE === WAIT
                   #puts @teamname + ' Waiting for La'
                   sleep 1
                   next
                end

                #Once we are in RUN mode check the first event then sleep till that time
                evOne = @singletonList.shift

                if !evOne.nil?
                    clock = parent_main.gameclock.gametime
                    if evOne.starttime > clock
                        sleep evOne.starttime - clock
                    end  
                    
                    if @teamname === 'Red Team'
                        puts evOne.name.to_s.red + " " + evOne.starttime.to_s.light_magenta + " " + parent_main.gameclock.gametime.to_s.green
                    else
                        puts evOne.name.to_s.light_cyan + " " + evOne.starttime.to_s.light_magenta + " " + parent_main.gameclock.gametime.to_s.green
                    end
            
                end

                if @singletonList.empty?
                    break
                end
            end


            puts @teamname + " Finished Executing."
        end
    end

end
