module OCCPGameServer

    class Team #Really the TeamScheduler

        attr_accessor :teamname, :teamid, :speedfactor, :teamhost
        attr_accessor :singletonList, :periodicList

        #Thread State Modes
        WAIT = 1
        READY = 2
        RUN = 3
        STOP = 4

        #The periodic events will be calculated in a block of the next future X seconds
        EVENT_PERIOD = 5
                   
        def initialize()

            require 'securerandom'
            
            #Create an Instance variable to hold our events
            @events = Array.new
            
            @rawevents = Array.new

            @STATE = WAIT
        
            @INBOX = Queue.new

            @periodThread = Array.new
            
            @singletonList = Array.new
            @periodicList = Array.new

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

        def set_state(state)

            case state
                when WAIT
                    if @STATE === RUN
                        @periodThread.each{|evThread|
                            evThread.stop
                        }
                    end
                when RUN
                    if @STATE === WAIT
                        @periodThread.each{|evThread|
                            evThread.wakeup
                        }
                    end
            end


            @STATE = state

        end

        def run(app_core)
          
            app_core.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>'Executing...'})
                       
            sort1 = Time.now
            #Sort into the order that they should be popped into the @eventRunQueue
            @singletonList.sort!{|aEv,bEv| aEv.starttime <=> bEv.starttime }
            sorttime = Time.now - sort1

            app_core.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>"Total sort time for #{@singletonList.size.to_s} events is #{sorttime}."})
            app_core.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>"Number of periodic events is #{@periodicList.count.to_s} events."})
            app_core.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>'READY'})
           

            #Launch a separate thread for each of the periodically scheduled events.
            @periodicList.each {|evOne|
                #next
                @periodThread << Thread.new {
              
                    if @STATE === WAIT
                        Thread.stop
                    end
                    # EventThread Run Loop
                    while true do
                    #   app_core.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>"Periodic Wake-Up at #{app_core.gameclock.gametime.to_s.green}"})
                        clock = app_core.gameclock.gametime
                        if evOne.starttime > clock 
                            sleep(evOne.starttime-clock) # don't wake up until the start time 
                            next
                        elsif evOne.endtime < clock
                            break
                        end

                        #run the event
                        
                        # Get the handler from the app_core and launch the event
                        event_handler = app_core.get_handler(evOne.eventhandler)
                        this_event = event_handler.run(evOne, app_core)

                        msgtext = "PERIODIC ".green + evOne.name.to_s.light_cyan + " " + clock.to_s.yellow + " " + evOne.frequency.to_s.light_magenta + " " + app_core.gameclock.gametime.to_s.green
                        app_core.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>msgtext})
                        

                        if evOne.freqscale === 'sec' 
                            sleepFor = 1/evOne.frequency
                            sleep(sleepFor)
                        
                        elsif evOne.freqscale === 'min'
                            sleepFor = 60/evOne.frequency
                            sleep(sleepFor)
                            
                        elsif evOne.freqscale === 'hour'
                            sleepFor = 3600/evOne.frequency
                            sleep(sleepFor)

                        else
                            next
                        end

                        #msgtext = evOne.name.to_s.light_cyan + " " + clock.to_s.yellow + " " + evOne.starttime.to_s.light_magenta + " " + app_core.gameclock.gametime.to_s.green
                        #msgtext = "Pushing #{nextLL.count.to_s.yellow} events on the run Queue"
                        #app_core.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>msgtext})

                    end # end EventThread while loop            
                }#end periodThread
            } #end periodicList


### RUN LOOP BEGINS ###
            resleep = nil
            sleeptime = 0

            #Signal ready and wait for start signal
            while true do
                
                if @STATE === WAIT
                   #puts @teamname + ' Waiting for La'
                   sleep 1
                   next
                end

                #if resleep.nil?
                    #Once we are in RUN mode check the first event then sleep till that time
                    evOne = @singletonList.shift

                    if !evOne.nil?
                        clock = app_core.gameclock.gametime
                        if evOne.starttime > clock
                            sleeptime = evOne.starttime - clock
                            #puts "#{@teamname} sleeping for #{sleeptime}"
                            sleep sleeptime
                        end  
                        levent = evOne
                        
                        # Get the handler from the app_core and launch the event
                        event_handler = app_core.get_handler(evOne.eventhandler)
                        this_event = event_handler.run(evOne, app_core)
                        
                        if @teamname === 'Red Team'
                            msgtext = evOne.name.to_s.light_red + " " + clock.to_s.yellow + " " + evOne.starttime.to_s.light_magenta + " " + app_core.gameclock.gametime.to_s.green
                            app_core.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>msgtext})
                        else
                            msgtext = evOne.name.to_s.light_cyan + " " + clock.to_s.yellow + " " + evOne.starttime.to_s.light_magenta + " " + app_core.gameclock.gametime.to_s.green
                            app_core.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>msgtext})
                        end
                    else
                        msgtext = clock.to_s.yellow + " " + levent.starttime.to_s.light_magenta + " " + app_core.gameclock.gametime.to_s.green
                        app_core.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>msgtext})

                        break
                    end
               # end
                
                #Now sleep until the next single event or when the periodic list needs recalculating
               # if sleeptime > EVENT_PERIOD
                #    resleep = sleeptime - EVENT_PERIOD
                 #   sleep EVENT_PERIOD
               # else
                #    resleep = nil
                 #   sleep sleeptime
                #end

            end

            @periodThread.join
            app_core.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>"Finished Executing."})
        end
    end

end
