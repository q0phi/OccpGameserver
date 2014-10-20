module OCCPGameServer

class Team #Really the TeamScheduler

    attr_accessor :teamname, :teamid, :speedfactor, :teamhost
    attr_accessor :singletonList, :periodicList, :INBOX
    attr_reader :STATE

    #Thread State Modes
    WAIT = 1
    READY = 2
    RUN = 3
    STOP = 4
    QUIT = 5

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

        @eventGroup = ThreadGroup.new
        @eventGroupSingle = ThreadGroup.new

        @shuttingdown = false

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
            @shuttingdown = true
            #Kill the PERIODIC Loops
            @periodThread.each{|evThread|
                if evThread.alive?
                    evThread.run
                end
            }
            if @singletonThread.alive?
                @singletonThread.run
            end
        end

    end


    def run(app_core)
        
        from = @teamname
        if @teamname == 'Red Team'
            from = @teamname.red
        elsif @teamname == 'Blue Team'
            from = @teamname.light_cyan
        end

        Log4r::NDC.set_max_depth(72)
        Log4r::NDC.push(from + ':')
        stackLocal = Log4r::NDC.clone_stack()
        
        $log.info('Executing...')

        sort1 = Time.now
        #Sort into the order that they should be popped into the @eventRunQueue
        @singletonList.sort!{|aEv,bEv| aEv.starttime <=> bEv.starttime }
        sorttime = Time.now - sort1

        $log.debug "Total sort time for #{@singletonList.size.to_s} events is #{sorttime}."
        $log.debug "Number of periodic events is #{@periodicList.count.to_s} events."
       

        #Launch a separate thread for each of the periodically scheduled events.
        @periodicList.each {|event|
            @periodThread << Thread.new {
        
                Log4r::NDC.set_max_depth(72)
                Log4r::NDC.inherit(stackLocal.clone)
                
                evOne = event

                $log.debug("Creating periodic thread scheduler for: #{evOne.name} #{evOne.eventuid}")
                #threaduid = evOne.eventuid
                sleepFor = 0
                drift = 0
                    
                loops = 0
                # Get the handler from the $appCore and launch the event
                event_handler = $appCore.get_handler(evOne.eventhandler)

                if @STATE === WAIT
                    Thread.stop
                end
                # Event Scheduler Thread Run Loop
                while not @shuttingdown do
                    
                    clock = $appCore.gameclock.gametime

                    #Stop running this event after its end time
                    if evOne.endtime < clock
                        break
                    end

                    # Keep sleeping until the start time or until the next iteration
                    while evOne.starttime > clock or sleepFor > 0

                        clock = $appCore.gameclock.gametime
                        #Special case while waiting to for starttime
                        startSleep = evOne.starttime - clock
                        if startSleep > 0
                            sleep(startSleep)
                        end

                        #Check if last sleep cycle was interupted and continue it if needed
                        if sleepFor > 0
                            preClock = $appCore.gameclock.gametime
                            sleep(sleepFor)
                            postClock = $appCore.gameclock.gametime
                            sleepFor = sleepFor - (postClock - preClock)
                        end

                        if sleepFor > 0 
                            $log.debug("Woke up #{evOne.name} #{evOne.eventuid}")
                        end
                        #If interupted from sleep in order to pause, stop quickly
                        if @STATE === WAIT
                            Thread.stop
                            #When we wakeup restart the sleep-loop
                            next
                        elsif @STATE === STOP
                            break
                            #$log.debug("CRUSHING EXIT".red)
                            #Thread.exit
                        end
                    end
                    
                    
                    if @STATE === STOP
                        break
                    end

                    #For now an event and it's handler code are going to be assumed to run atomically from the scheduler
                    #IE once the handler has launched it can do whatever it wants until it returns
                    #If the GS is paused while it is running tough beans for us.
                    eventLocal = Thread.new do

                        launchAt = $appCore.gameclock.gametime
                        
                        Log4r::NDC.set_max_depth(72)
                        Log4r::NDC.inherit(stackLocal.clone)
                        $log.debug("Launching Periodic Event: #{evOne.name} #{evOne.eventuid.light_magenta} at #{launchAt.round(4)} for the #{loops} time")

                        #Run the event through its handler
                        event_handler.run(evOne, app_core)

                        slept = evOne.frequency + drift
                        msgtext = "PERIODIC ".green + evOne.name.to_s.light_magenta + " " +
                            launchAt.round(4).to_s.yellow + " " + evOne.frequency.to_s.light_magenta + " " + slept.to_s.light_magenta + " " + $appCore.gameclock.gametime.round(4).to_s.green
                        
                        $log.debug msgtext

                    end
                    
                    #Stats counter is for debugging only
                    loops = loops + 1

                    @eventGroup.add(eventLocal)

                    drift = evOne.drift.eql?(0.0) ? 0.0 : Random.rand(evOne.drift*2)-(evOne.drift)
                    sleepFor = evOne.frequency + drift
                   
                end # end Event Scheduler Thread Loop
                $log.debug("Exiting scheduler loop for: #{evOne.name} #{evOne.eventuid}".red)
            }#end periodThread
        } #end periodicList

        ### Sparse Event Run Thread ###
        @singletonThread = Thread.new {

            Log4r::NDC.set_max_depth(72)
            Log4r::NDC.inherit(stackLocal.clone)
            
           
            $log.debug('Length of singleton list: ' + @singletonList.length.to_s)

            if @STATE === WAIT
                Thread.stop
            end

            #Signal ready and wait for start signal
            while not @shuttingdown do
                
                $log.debug "Re-sorting singleton list"
                @singletonList.sort!{|aEv,bEv| aEv.starttime <=> bEv.starttime }

                # Search for the next single event to run
                currentEvent = nil
                @singletonList.each do |event|
                    clock = $appCore.gameclock.gametime
                    if event.starttime >= clock and not event.hasrun
                        currentEvent = event
                        break
                    end
                end

                if currentEvent

                    $log.debug('Event loaded: ' + currentEvent.name + ' ' + currentEvent.eventuid)

                    sleeptime = 0
                    clock = $appCore.gameclock.gametime
                    if currentEvent.starttime > clock
                        sleeptime = currentEvent.starttime - clock
                        sleep sleeptime
                    end  
                    
                    #If interupted from sleep in order to pause, stop quickly
                    if @STATE === WAIT
                        Thread.stop
                        #When we wakeup restart the loop to check the start time
                        next
                    elsif @STATE === STOP
                        break
                    end
                   
                    evOne = currentEvent.clone
                    
                    eventLocal = Thread.new do
                        
                        Log4r::NDC.set_max_depth(72)
                        Log4r::NDC.inherit(stackLocal.clone)
                       
                        launchAt = $appCore.gameclock.gametime

                        if evOne.nil?
                            $log.error("How did I get here at #{launchAt.to_s}".red)
                            return
                        end

                        $log.info("Launching Single Event: #{evOne.name} #{evOne.eventuid.light_magenta} at #{launchAt.round(4)}")
                        
                        # Get the handler from the app_core and launch the event
                        event_handler = $appCore.get_handler(evOne.eventhandler)
                        event_handler.run(evOne, app_core)

                        #Update this events status
                        @singletonList.each do |event|
                            if event.eventuid == evOne.eventuid
                                event.setrunstate(true)
                                break
                            end
                        end

                        msgtext = 'SINGLETON '.green + "#{evOne.name.to_s.light_magenta} #{evOne.eventuid.to_s.light_magenta} at #{launchAt.round(4).to_s.yellow} end #{$appCore.gameclock.gametime.round(4).to_s.green}"
                        
                        $log.debug msgtext

                    end

                    @eventGroupSingle.add(eventLocal)

                    #TODO Keep this thread alive so users can add additional single events to it.
                else
                    while not @eventGroupSingle.list.empty? do
                        $log.debug 'Waiting for all events to complete -- re-sleeping'
                        sleep(1)
                    end
                    $log.info "Finished Running All Singleton Events at: ".light_green + $appCore.gameclock.gametime.to_s.green
                    break

                end
            end
            
            $log.debug('Exiting Singleton Thread')
        }#End Singleton thread

        #Check that everything is setup
        $log.info 'READY'
        
        #TEAM run Loop
        while not @shuttingdown and message = @INBOX.pop do
            case message.signal                
            
            when 'STATUS'
                $log.debug 'Status Request'

            when 'COMMAND'

                command = message.msg
                
                case command[:command]
                when 'STATE'
                    set_state(command[:state])
                end


            when 'DIE'
                break
            else
                $log.error 'Unknown message received: ' + message.to_s
            end

        end #Message Poll End

        @periodThread.each {|thr|
            thr.join
        }
        @eventGroup.list.each{|ev|
            ev.join
        }
        @eventGroupSingle.list.each{|ev|
            ev.join
        }
        @singletonThread.join

        $log.info "Finished executing, Team thread terminating".red

    end #Run End
end #Class End
end #Module End
