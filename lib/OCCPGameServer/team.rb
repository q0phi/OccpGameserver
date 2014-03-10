module OCCPGameServer

class Team #Really the TeamScheduler

    attr_accessor :teamname, :teamid, :speedfactor, :teamhost
    attr_accessor :singletonList, :periodicList, :INBOX

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
        @singletonThread = Array.new
        
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

        oldstate = @STATE
        @STATE = state

        case state
            when WAIT
                if oldstate === RUN
                    @periodThread.each{|evThread|
                        if evThread.alive?
                            evThread.run
                        end
                    }
                    #puts @singletonThread.inspect
                    if @singletonThread.alive?
                        @singletonThread.run
                    end
                end
            when RUN
                if oldstate === WAIT
                    @periodThread.each{|evThread|
                        if evThread.alive?
                            evThread.wakeup
                        end
                    }
                    if @singletonThread.alive?
                        @singletonThread.wakeup
                    end
                end
            when STOP
                #Kill the PERIODIC Loops
                @periodThread.each{|evThread|
                    if evThread.alive?
                            evThread.run
                        end
                }
                if @singletonThread.alive?
                    @singletonThread.run
                end
                exit_cleanup()

        end

    end

    #Cleanup any residuals and wait for related threads to shutdown nicely
    def exit_cleanup()

        periodRelease = false
        singleRelease = false

        while not periodRelease and singleRelease
        # Poll each thread until there all dead
            if @periodThread.empty?
                periodRelease = true
            end
            
            @periodThread.delete_if{|evThread|
                not evThread.alive?
            }

            if not @singletonThread.alive?
                singleRelease = true
            end
        end

        $log.debug 'Thread cleanup complete'
        Thread.exit
    end


    def run(app_core)
      
        #app_core.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>'Executing...'})
        Log4r::NDC.push(@teamname + ':')
        $log.info('Executing...')

        sort1 = Time.now
        #Sort into the order that they should be popped into the @eventRunQueue
        @singletonList.sort!{|aEv,bEv| aEv.starttime <=> bEv.starttime }
        sorttime = Time.now - sort1

        $log.debug "Total sort time for #{@singletonList.size.to_s} events is #{sorttime}."
        $log.debug "Number of periodic events is #{@periodicList.count.to_s} events."
       

        #Launch a separate thread for each of the periodically scheduled events.
        @periodicList.each {|evOne|
            #next
            @periodThread << Thread.new {
          
                from = @teamname
                if @teamname == 'Red Team'
                    from = @teamname.red
                elsif @teamname == 'Blue Team'
                    from = @teamname.light_cyan
                end

                Log4r::NDC.push(from + ':')

                sleepFor = 0
                    
                # Get the handler from the app_core and launch the event
                event_handler = app_core.get_handler(evOne.eventhandler)

                if @STATE === WAIT
                    Thread.stop
                end
                # EventThread Run Loop
                while true do
                    
                    clock = app_core.gameclock.gametime

                    #Stop running this event after its end time
                    if evOne.endtime < clock
                        break
                    end

                    # Keep sleeping until the start time or until the next iteration
                    while evOne.starttime > clock or sleepFor > 0

                        #Special case while waiting to for starttime
                        startSleep = evOne.starttime - clock
                        if startSleep > 0
                            sleep(startSleep)
                        end

                        if sleepFor > 0
                            preClock = app_core.gameclock.gametime
                            sleep(sleepFor)
                            clock = app_core.gameclock.gametime
                            sleepFor = sleepFor - (clock - preClock)
                        end

                        #If interupted from sleep in order to pause, stop quickly
                        if @STATE === WAIT
                            Thread.stop
                            #When we wakeup restart the loop
                            next
                        end
                    end
                    
                    
                    if @STATE === STOP
                        break
                    end

                    #Run the event through its handler
                    this_event = event_handler.run(evOne, app_core)

                    msgtext = "PERIODIC ".green + evOne.name.to_s.light_cyan + " " +
                        clock.round(4).to_s.yellow + " " + evOne.frequency.to_s.light_magenta + " " + app_core.gameclock.gametime.round(4).to_s.green
                    
                    $log.debug msgtext

                    sleepFor = evOne.period
                   
                end # end EventThread while loop            
            }#end periodThread
        } #end periodicList


        ### Sparse Event Run Thread ###
        @singletonThread = Thread.new {

            from = @teamname
            if @teamname == 'Red Team'
                from = @teamname.red
            elsif @teamname == 'Blue Team'
                from = @teamname.light_cyan
            end

            Log4r::NDC.push(from + ':')
            
            inSleepCycle = false
            sleeptime = 0

            if @STATE === WAIT
                Thread.stop
            end

            #Grab the first event to be run
            evOne = @singletonList.shift

            #Signal ready and wait for start signal
            while true do
                
                if !evOne.nil?

                    clock = app_core.gameclock.gametime
                    if evOne.starttime > clock
                        sleeptime = evOne.starttime - clock
                        sleep sleeptime
                    end  
                    
                    #If interupted from sleep in order to pause, stop quickly
                    if @STATE === WAIT
                        inSleepCycle = true
                        Thread.stop
                        #When we wakeup restart the loop
                        next
                    elsif @STATE === STOP
                        break
                    end

                    
                    levent = evOne
                    
                    # Get the handler from the app_core and launch the event
                    event_handler = app_core.get_handler(evOne.eventhandler)
                    this_event = event_handler.run(evOne, app_core)
                   
                    
                    msgtext = evOne.name.to_s.light_cyan + " " + clock.round(4).to_s.yellow + " " + evOne.starttime.to_s.light_magenta + " " + app_core.gameclock.gametime.round(4).to_s.green
                
                    $log.debug msgtext
                    
                    #    app_core.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>msgtext})
                else

                    $log.info "Finished Running All Singleton Events at: ".light_red + app_core.gameclock.gametime.to_s.green
                    break

                end
                          
                #Grab the next single event
                evOne = @singletonList.shift

            end
        }

        $log.info 'READY'
        
        #TEAM run Loop
        while message = @INBOX.pop do
            case message.signal                
            
            when 'COMMAND'

                command = message.msg
                
                case command[:command]
                when 'STATE'
                    set_state(command[:state])
                end


            when 'DIE'
                break
            else
                break
            end



        end #Message Poll End

        @periodThread.join
        $log.debug "Finished executing, thread terminating"

    end #Run End
end #Class End
end #Module End
