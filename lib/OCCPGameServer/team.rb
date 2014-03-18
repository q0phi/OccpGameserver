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

        @eventGroup = ThreadGroup.new

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
      
        Log4r::NDC.set_max_depth(72)
        
        from = @teamname
        if @teamname == 'Red Team'
            from = @teamname.red
        elsif @teamname == 'Blue Team'
            from = @teamname.light_cyan
        end

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
            #next
            @periodThread << Thread.new {
        
                Log4r::NDC.set_max_depth(72)
                Log4r::NDC.inherit(stackLocal)
                
                evOne = event.clone
                $log.debug("Creating periodic thread scheduler for: #{evOne.name} #{evOne.eventuid}")
                #threaduid = evOne.eventuid
                sleepFor = 0
                    
                # Get the handler from the app_core and launch the event
                event_handler = app_core.get_handler(evOne.eventhandler)

                if @STATE === WAIT
                    Thread.stop
                end
                # Event Scheduler Thread Run Loop
                while not @shuttingdown do
                    
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

                        #Check if last sleep cycle was interupted and continue it if needed
                        if sleepFor > 0
                            preClock = app_core.gameclock.gametime
                            sleep(sleepFor)
                            clock = app_core.gameclock.gametime
                            sleepFor = sleepFor - (clock - preClock)
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

                    stackLocal = Log4r::NDC.clone_stack()
                    
                    eventLocal = Thread.new do

                        launchAt = app_core.gameclock.gametime
                        Log4r::NDC.set_max_depth(72)

                        Log4r::NDC.inherit(stackLocal)

                        #Run the event through its handler
                        this_event = event_handler.run(evOne, app_core)

                        msgtext = "PERIODIC ".green + evOne.name.to_s.light_magenta + " " +
                            launchAt.round(4).to_s.yellow + " " + evOne.frequency.to_s.light_magenta + " " + app_core.gameclock.gametime.round(4).to_s.green
                        
                        $log.debug msgtext

                    end

                    @eventGroup.add(eventLocal)

                    sleepFor = evOne.period
                   
                end # end Event Scheduler Thread Loop
                $log.debug("Exiting scheduler loop for: #{evOne.name} #{evOne.eventuid}".red)
            }#end periodThread
        } #end periodicList

        singles = 0
        ### Sparse Event Run Thread ###
        @singletonThread = Thread.new {

            Log4r::NDC.set_max_depth(72)
            Log4r::NDC.inherit(stackLocal)
            
            sleeptime = 0
           
            $log.debug('Length of singleton list: ' + @singletonList.length.to_s)

            #Grab the first event to be run
            nextEvent = @singletonList.shift
            singles += 1
            $log.debug('First event popped: '.yellow + singles.to_s)

            if @STATE === WAIT
                Thread.stop
            end

            #Signal ready and wait for start signal
            while not @shuttingdown do
                
                if nextEvent

                    $log.debug('Event loaded: ' + nextEvent.name + ' ' + nextEvent.eventuid)

                    clock = app_core.gameclock.gametime
                    if nextEvent.starttime > clock
                        sleeptime = nextEvent.starttime - clock
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
                   
                    evOne = nextEvent.clone
                    
                    eventLocal = Thread.new do
                        
                        Log4r::NDC.set_max_depth(72)
                        Log4r::NDC.inherit(stackLocal)
                        
                        launchAt = app_core.gameclock.gametime

                        if evOne.nil?
                            $log.debug("How did I get here at #{launchAt.to_s}")
                            return
                        end

                        $log.debug("Launching #{evOne.name} #{evOne.eventuid}")
                        
                        # Get the handler from the app_core and launch the event
                        event_handler = app_core.get_handler(evOne.eventhandler)
                        this_event = event_handler.run(evOne, app_core)

                        msgtext = evOne.name.to_s.light_magenta + " " +
                            launchAt.round(4).to_s.yellow + " " + evOne.frequency.to_s.light_magenta + " " + app_core.gameclock.gametime.round(4).to_s.green
                        
                        $log.debug msgtext

                    end

                    @eventGroup.add(eventLocal)

                else

                    $log.info "Finished Running All Singleton Events at: ".light_green + app_core.gameclock.gametime.to_s.green
                    break

                end
                          
                #Grab the next single event
                nextEvent = @singletonList.shift
                singles += 1
                $log.debug('Num Pop\'d: '.yellow + singles.to_s + ' At: '.yellow + app_core.gameclock.gametime.to_s + ' NIL? '.yellow + nextEvent.nil?.to_s)

            end
            
            $log.debug('Exiting Singleton Thread')
        }#End Singleton thread

        $log.info 'READY'
        
        #TEAM run Loop
        while message = @INBOX.pop do
            case message.signal                
            
            when 'STATUS'
                @eventGroup.list.each{|eventThread|
                    $log.debug(eventThread.status)
                }

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

            if @shuttingdown
                break
            end

        end #Message Poll End

        @periodThread.each {|thr|
            thr.join
        }
        @eventGroup.list.each{|ev|
            ev.join
        }
        @singletonThread.join

        $log.debug "Finished executing, Team thread terminating".red

    end #Run End
end #Class End
end #Module End
