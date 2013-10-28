module OCCPGameServer

    class Team #Really the TeamScheduler

        attr_accessor :teamname, :teamid, :speedfactor, :teamhost

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

            @STATE = RUN
        
            @INBOX = Queue.new


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
                    for i in 0..20
                        event.starttime = rand 90 
                        @singletonList << event.clone
                    end
                else
                    @periodicList << event
                end
            }
           
            sort1 = Time.now
            #Sort into the order that they should be popped into the @eventRunQueue
            @singletonList.sort!{|aEv,bEv| aEv.starttime <=> bEv.starttime }
            sorttime = Time.now - sort1

            parent_main.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>"Total sort time for #{@singletonList.size.to_s} events is #{sorttime}."})
            parent_main.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>"Number of periodic events is #{@periodicList.count.to_s} events."})
            parent_main.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>'READY'})
           

            #Launch a separate thread for the periodically scheduled events.
            periodThread = Thread.new {
                while true do

                    parent_main.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>"Periodic Wake-Up at #{parent_main.gameclock.gametime.to_s.green}"})
                    #Process the next block of periodic events
                    @periodicList.each {|evOne|

                        nextLL = Array.new #event prepped for next launch
                        
                        clock = parent_main.gameclock.gametime
                        if evOne.starttime > clock or evOne.endtime < clock
                            next
                        end

                        if evOne.freqscale === 'sec' 
                    
                            numrun = evOne.frequency * EVENT_PERIOD
                            numrun.to_i.times { |i|
                                evOne.eventuid = SecureRandom.uuid
                                parent_main.eventRunQueue << evOne
                                nextLL << evOne
                            }
                        
                        elsif evOne.freqscale === 'min'
                            numperiod = evOne.frequency / 60
                            numtorun = numperiod * EVENT_PERIOD
                            rollover = evOne.rollover
                            if !rollover.nil?
                                numruntotal = rollover + numtorun
                                numrun = numruntotal.to_i
                                evOne.rollover = numruntotal % 1
                            else
                                numrun = numtorun.to_i
                                evOne.rollover = numtorun % 1
                            end
                            numrun.to_i.times { |i|
                                evOne.eventuid = SecureRandom.uuid
                                parent_main.eventRunQueue << evOne
                                nextLL << evOne
                            }

                        elsif evOne.freqscale === 'hour'
                            numperiod = evOne.frequency / 3600
                            numtorun = numperiod * EVENT_PERIOD
                            rollover = evOne.rollover
                            if !rollover.nil?
                                numruntotal = rollover + numtorun
                                numrun = numruntotal.to_i
                                evOne.rollover = numruntotal % 1
                            else
                                numrun = numtorun.to_i
                                evOne.rollover = numtorun % 1
                            end
                            numrun.to_i.times { |i|
                                evOne.eventuid = SecureRandom.uuid
                                parent_main.eventRunQueue << evOne
                                nextLL << evOne
                            }

                        else
                            next
                        end

                        #msgtext = evOne.name.to_s.light_cyan + " " + clock.to_s.yellow + " " + evOne.starttime.to_s.light_magenta + " " + parent_main.gameclock.gametime.to_s.green
                        msgtext = "Pushing #{nextLL.count.to_s.yellow} events on the run Queue"
                        parent_main.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>msgtext})


                    }
                    
                    sleep EVENT_PERIOD
                end # end major while loop
            
            }#end periodThread


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
                        clock = parent_main.gameclock.gametime
                        if evOne.starttime > clock
                            sleeptime = evOne.starttime - clock
                            #puts "#{@teamname} sleeping for #{sleeptime}"
                            sleep sleeptime
                        end  
                        levent = evOne
                        if @teamname === 'Red Team'
                            msgtext = evOne.name.to_s.light_red + " " + clock.to_s.yellow + " " + evOne.starttime.to_s.light_magenta + " " + parent_main.gameclock.gametime.to_s.green
                            parent_main.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>msgtext})
                        else
                            msgtext = evOne.name.to_s.light_cyan + " " + clock.to_s.yellow + " " + evOne.starttime.to_s.light_magenta + " " + parent_main.gameclock.gametime.to_s.green
                            parent_main.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>msgtext})
                        end
                    else
                        msgtext = clock.to_s.yellow + " " + levent.starttime.to_s.light_magenta + " " + parent_main.gameclock.gametime.to_s.green
                        parent_main.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>msgtext})

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

periodThread.join
            parent_main.INBOX << GMessage.new({:fromid=>@teamname,:signal=>'CONSOLE', :msg=>"Finished Executing."})
        end
    end

end
