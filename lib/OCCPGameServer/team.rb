module OCCPGameServer

class Team #Really the TeamScheduler

    attr_accessor :teamname, :teamid, :speedfactor, :teamhost
    attr_accessor :singletonList, :periodicList, :INBOX
    attr_accessor :singletonThread, :eventGroup
    attr_reader :STATE

    def initialize()

        require 'securerandom'
        
        #Create an Instance variable to hold our events
        @events = Array.new
        
        @rawevents = Array.new

        @STATE = WAIT
    
        @INBOX = Queue.new

        @periodThreads = ThreadGroup.new
        @singletonThread = nil
        
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

        raise InvalidState, "invalid state value sent: #{state}" if !OCCPGameServer.valid_state(state)
        stateName = OCCPGameServer.constant_by_value(state)
        $log.debug "Team #{@teamname} changing state to #{stateName}"

        oldstate = @STATE
        @STATE = state

        case state
        when WAIT
            if oldstate === RUN
                @periodThreads.list.each{|evSchedThr|
                    evSchedThr.run
                }
                if @singletonThread.alive?
                    @singletonThread.run
                end
            end
        when RUN
            if oldstate === WAIT
                @periodThreads.list.each{|evSchedThr|
                    evSchedThr.wakeup
                }
                if @singletonThread.alive?
                    @singletonThread.wakeup
                end
            end
        when STOP
            @shuttingdown = true
            #Kill the PERIODIC Loops
            @periodThreads.list.each{|evSchedThr|
                evSchedThr.run
            }
            if @singletonThread.alive?
                @singletonThread.run
            end
        end

    end

    ##
    # Jump the current process to a new namespace
    #
    def namespace_jump(evOne)

        netNS = nil
        # Setup the execution space
        # IE get a network namespace for this execution for the given IP address
        if evOne.ipaddress != nil
            ipPool = $appCore.get_ip_pool(evOne.ipaddress)
            if !ipPool.nil? and ipPool[:ifname] != nil 
                ipAddr = ipPool[:addresses][rand(ipPool[:addresses].length)]
                netInfo = {:iface => ipPool[:ifname], :ipaddr => ipAddr , :cidr => ipPool[:cidr], :gateway => ipPool[:gateway] }
                begin
                    netNS = $appCore.get_netns(netInfo) 
                rescue ArgumentError => e
                    msg = "unable to create network namespace for event #{evOne.name} - #{e.message}; aborting execution"
                    print msg.red
                    $log.error msg.red
                    return nil
                end
                
                # Change to the correct network namespace if provided
                fd = IO.sysopen('/var/run/netns/' + netNS.nsName, 'r')
                $setns.call(fd, 0)
                IO.new(fd, 'r').close

            else
                $log.debug "WARNING unable to run #{evOne.name} with invalid pool definition; aborting execution".light_yellow
            end
        else
            $log.debug "WARNING event #{evOne.name} does not specify an ip address pool to send from".light_yellow
        end

        return netNS
    end


    ##
    # Main run loop for the a team
    #
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
            periodThread = Thread.new {
        
                Log4r::NDC.set_max_depth(72)
                Log4r::NDC.inherit(stackLocal.clone)
                
                evOne = event

                $log.debug("Creating periodic thread scheduler for: #{evOne.name} #{evOne.eventuid}")
                #threaduid = evOne.eventuid
                
                # Get the handler from the $appCore and launch the event
                event_handler = $appCore.get_handler(evOne.eventhandler)

                drift = 0    
                loops = 0
                periodSleepCycle = 0
                runOnce = false
                # Event Scheduler Thread Run Loop
                while not @shuttingdown do
                    
                    #If interupted from sleep in order to pause, stop quickly
                    if @STATE === WAIT
                        Thread.stop
                        #When we wakeup restart the sleep-loop
                        next
                    elsif @STATE === STOP
                        break
                    end
                    
                    clock = $appCore.gameclock.gametime

                    # Keep sleeping until the start time
                    if evOne.starttime > clock
                        startSleep = evOne.starttime - clock
                        sleep(startSleep)
                        next # When we wakeup check the STATE

                    #Stop running this event after its end time
                    elsif evOne.endtime < clock
                        break
                    
                    #Sleep for one full period
                    elsif periodSleepCycle > 0.0
                        preClock = $appCore.gameclock.gametime
                        sleep(periodSleepCycle) # We don't use sleep return because it is rounded
                        postClock = $appCore.gameclock.gametime
                        periodActualSleep = postClock - preClock
                        periodSleepCycle -= periodActualSleep 
                        if periodSleepCycle > 0.0
                            next # We have been interupted so check STATE
                        end
                    elsif runOnce #We have just run and it is time to sleep for one new period

                        # Calculate or next sleep period
                        drift = evOne.drift.eql?(0.0) ? 0.0 : Random.rand(evOne.drift*2)-(evOne.drift)
                        periodSleepCycle = evOne.frequency + drift

                        preClock = $appCore.gameclock.gametime
                        sleep(periodSleepCycle) # We don't use sleep return because it is rounded
                        postClock = $appCore.gameclock.gametime
                        periodActualSleep = postClock - preClock
                        
                        #$log.debug "gametime: #{postClock.round(4)} periodSleepCycle: #{periodSleepCycle} periodActualSleep: #{periodActualSleep.round(4)}"
                        periodSleepCycle -= periodActualSleep
                        if periodSleepCycle > 0.0
                            next # We have been interupted so check STATE
                        elsif evOne.endtime < postClock
                            break #if we over slept stop running
                        end 

                        #$log.debug("Woke up #{evOne.name} #{evOne.eventuid}")
                    end
                    $log.debug "Starting next launch"
                    runOnce = true

                    #For now an event and it's handler code are going to be assumed to run atomically from the scheduler
                    #IE once the handler has launched it can do whatever it wants until it returns
                    #If the GS is paused while it is running tough beans for us.
                    eventLocal = Thread.new do

                        Log4r::NDC.set_max_depth(72)
                        Log4r::NDC.inherit(stackLocal.clone)
                
                        #TODO if nil is returned we may want to abort execution?
                        netNS = namespace_jump(evOne)

                        launchAt = $appCore.gameclock.gametime
                        thisloop = loops
                        $log.debug("Launching Periodic Event: #{evOne.name} #{evOne.eventuid.light_magenta} at #{launchAt.round(4)} for the #{thisloop} time")

                        begin

                            #Run the event through its handler
                            runResult = event_handler.run(evOne, app_core)

                            finishAt = $appCore.gameclock.gametime
                            slept = evOne.frequency + drift
                            msgtext = "PERIODIC Scheduler: ".green + evOne.name.to_s.light_magenta + " #{thisloop} " +
                                launchAt.round(4).to_s.yellow + " " + evOne.frequency.to_s.light_magenta + " " +
                                slept.to_s.light_magenta + " " + finishAt.round(4).to_s.green

                            $log.debug msgtext
                            runResult[:scores].each {|score|
                                score.merge!({:eventuid => evOne.eventuid, :eventid => evOne.eventid, 
                                                :gametime => finishAt })
                                app_core.INBOX << GMessage.new({:fromid=>'Team',:signal=>'SCORE', :msg=>score})
                            }
                            msgHash = runResult.merge({:eventname => evOne.name, :eventid=> evOne.eventid, :eventuid=> evOne.eventuid, 
                                                      :starttime => launchAt, :endtime => finishAt })
                            $appCore.INBOX << GMessage.new({:fromid=>'Team', :signal=>'EVENTLOG', :msg=>msgHash })

                        rescue Exception => e

                            $log.warn "Periodic Event: #{evOne.name} #{evOne.eventuid.light_magenta} error: #{e.message}"

                        end
                        
                        # Release the namespace
                        if !netNS.nil?
                            $appCore.release_netns(netNS.nsName)
                        end

                    end
                    
                    #Stats counter is for debugging only
                    loops = loops + 1

                    @eventGroup.add(eventLocal)
                   
                end # end Event Scheduler Thread Loop
                $log.debug("Exiting scheduler loop for: #{evOne.name} #{evOne.eventuid}".red)
            }#end periodThread
            @periodThreads.add(periodThread)
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
                        sleeptime = currentEvent.starttime - clock  # TODO This section needs to be rethought if we are 
                        sleep sleeptime                             # going to support adding events into this list dynamically
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
                    if evOne.nil?
                        $log.error("Popped an invalid singleton event from the list".red)
                        next
                    end

                    eventLocal = Thread.new do
                        
                        Log4r::NDC.set_max_depth(72)
                        Log4r::NDC.inherit(stackLocal.clone)
                       
                        launchAt = $appCore.gameclock.gametime
                        $log.info("Launching Single Event: #{evOne.name} #{evOne.eventuid.light_magenta} at #{launchAt.round(4)}")
                        
                        #TODO if nil is returned we may want to abort execution?
                        netNS = namespace_jump(evOne)
                        
                        begin

                            # Get the handler from the app_core and launch the event
                            event_handler = $appCore.get_handler(evOne.eventhandler)
                            runResult = event_handler.run(evOne, app_core)

                            finishAt = $appCore.gameclock.gametime
                        
                            msgtext = 'SINGLETON '.green + "#{evOne.name.to_s.light_magenta} #{evOne.eventuid.to_s.light_magenta}" + 
                                        " at #{launchAt.round(4).to_s.yellow} end #{finishAt.round(4).to_s.green}" 
                            $log.debug msgtext
                            
                            # Process Scoring Data
                            runResult[:scores].each {|score|
                                score.merge!({:eventuid => evOne.eventuid, :eventid => evOne.eventid, 
                                                :gametime => finishAt })
                                app_core.INBOX << GMessage.new({:fromid=>'Team',:signal=>'SCORE', :msg=>score})
                            }
                            
                            # Process the EventLog data
                            msgHash = runResult.merge({:eventname => evOne.name, :eventid=> evOne.eventid, :eventuid=> evOne.eventuid, 
                                                      :starttime => launchAt, :endtime => finishAt })
                            $appCore.INBOX << GMessage.new({:fromid=>'Team', :signal=>'EVENTLOG', :msg=>msgHash })

                        rescue Exception => e

                            $log.warn "Singleton Event: #{evOne.name} #{evOne.eventuid.light_magenta} error: #{e.message}"

                        end
                        
                        # Release the namespace
                        if !netNS.nil?
                            $appCore.release_netns(netNS.nsName)
                        end
                        
                        # Update this events run status in the master event list
                        @singletonList.each do |event|
                            if event.eventuid == evOne.eventuid
                                event.setrunstate(true)
                                break
                            end
                        end

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

        @periodThreads.list.each {|thr|
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
